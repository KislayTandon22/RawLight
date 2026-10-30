//! C ABI over the engine's command contract.
//!
//! A native UI owns an opaque [`RlSession`] and talks to it with JSON only:
//! `rl_execute(session, "develop.set", "{\"control\":\"light.exposure\",\"value\":0.35}")`.
//! Every returned string is owned by the caller and released with [`rl_string_free`].
//! Replies are `{"ok": <value>}` or `{"error": "<message>"}`; nothing here panics across the FFI.

use std::ffi::{CStr, CString, c_char};
use std::panic::{AssertUnwindSafe, catch_unwind};

use lightcraft_engine::Session;
use serde_json::{Value, json};

/// `app.export` is a UI-level command in the desktop app (it needs the app's writer); the bridge runs the
/// same engine export directly. Params as the engine documents: `path` (one exact file) or `dir`, `ids`
/// (default: the active photo), format, quality, size, colour space...
fn export(s: &mut Session, p: &Value) -> Result<Value, String> {
    use lightcraft_engine::export::{Destination, ExportFormat, ExportOptions, export_batch, write_file};
    let p = &s.export_params(p)?;
    let mut opts = ExportOptions::from_params(p).map_err(|e| e.to_string())?;
    if let (Some(path), None) = (p.get("path").and_then(Value::as_str), p.get("format")) {
        let ext = path.rsplit_once('.').map_or("", |(_, e)| e);
        opts.format = ExportFormat::parse(ext).unwrap_or(opts.format);
    }
    let ids: Vec<_> = match p.get("ids").and_then(Value::as_array) {
        Some(a) => a.iter().filter_map(|v| serde_json::from_value(v.clone()).ok()).collect(),
        None => s.active().into_iter().collect(),
    };
    if ids.is_empty() {
        return Err("no photo selected".into());
    }
    let exact = p.get("path").and_then(Value::as_str).filter(|x| !x.trim().is_empty()).map(str::to_string);
    let dir = p.get("dir").and_then(Value::as_str).unwrap_or_default().trim().to_string();
    if dir.is_empty() && exact.is_none() {
        return Err("choose an output folder".into());
    }
    let to = Destination { dir, exact };
    let files = export_batch(s, &ids, &opts, &to, &mut |path, bytes| write_file(path, bytes), &|path| std::path::Path::new(path).exists())?;
    Ok(json!({"files": files}))
}

/// Opaque session handle.
pub struct RlSession(Session);

fn reply(v: Value) -> *mut c_char {
    // JSON text never contains an interior NUL, so this cannot fail.
    CString::new(v.to_string()).map_or(std::ptr::null_mut(), CString::into_raw)
}

/// New empty session (`demo` non-zero loads the generated demo library).
#[unsafe(no_mangle)]
pub extern "C" fn rl_session_new(demo: i32) -> *mut RlSession {
    let s = catch_unwind(|| {
        let base = if demo != 0 { Session::with_demo() } else { Session::new() };
        base.with_fs().with_default_denoise_models().with_system_clock()
    });
    match s {
        Ok(s) => Box::into_raw(Box::new(RlSession(s))),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Open (or create) the persistent library in `dir`; `seed_demo` fills a new one with the demo photos.
/// Returns `{"ok":...}` / `{"error":...}`; free with [`rl_string_free`].
///
/// # Safety
/// `session` from [`rl_session_new`]; `dir` NUL-terminated.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rl_open_library(session: *mut RlSession, dir: *const c_char, seed_demo: i32) -> *mut c_char {
    let Some(session) = (unsafe { session.as_mut() }) else { return reply(json!({"error": "null session"})) };
    if dir.is_null() {
        return reply(json!({"error": "null dir"}));
    }
    let Ok(dir) = unsafe { CStr::from_ptr(dir) }.to_str() else { return reply(json!({"error": "dir is not UTF-8"})) };
    match catch_unwind(AssertUnwindSafe(|| session.0.open_library(dir, seed_demo != 0).map(|_| ()))) {
        Ok(Ok(())) => reply(json!({"ok": true})),
        Ok(Err(e)) => reply(json!({"error": e.to_string()})),
        Err(_) => reply(json!({"error": "internal panic"})),
    }
}

/// Run command `id` with JSON `params` (null or empty means no params).
///
/// # Safety
/// `session` must come from [`rl_session_new`]; `id` and `params` must be NUL-terminated or null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rl_execute(session: *mut RlSession, id: *const c_char, params: *const c_char) -> *mut c_char {
    let Some(session) = (unsafe { session.as_mut() }) else {
        return reply(json!({"error": "null session"}));
    };
    if id.is_null() {
        return reply(json!({"error": "null command id"}));
    }
    let Ok(id) = unsafe { CStr::from_ptr(id) }.to_str() else {
        return reply(json!({"error": "command id is not UTF-8"}));
    };
    let params: Value = if params.is_null() {
        Value::Null
    } else {
        match unsafe { CStr::from_ptr(params) }.to_str().map(|t| if t.trim().is_empty() { Ok(Value::Null) } else { serde_json::from_str(t) }) {
            Ok(Ok(v)) => v,
            Ok(Err(e)) => return reply(json!({"error": format!("bad params JSON: {e}")})),
            Err(_) => return reply(json!({"error": "params are not UTF-8"})),
        }
    };
    let run = || if id == "app.export" { export(&mut session.0, &params).map_err(|e| e.to_string()) } else { session.0.execute(id, &params).map_err(|e| e.to_string()) };
    match catch_unwind(AssertUnwindSafe(run)) {
        Ok(Ok(v)) => reply(json!({"ok": v})),
        Ok(Err(e)) => reply(json!({"error": e.to_string()})),
        Err(_) => reply(json!({"error": "internal panic"})),
    }
}

/// JSON array of the photo ids in the current view, in display order.
///
/// # Safety
/// `session` must come from [`rl_session_new`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rl_visible_ids(session: *mut RlSession) -> *mut c_char {
    let Some(session) = (unsafe { session.as_mut() }) else {
        return reply(json!({"error": "null session"}));
    };
    let ids: Vec<u64> = session.0.visible_cloned().iter().map(|i| i.0).collect();
    reply(json!({"ok": ids}))
}

/// Render photo `id` with its current edits, fitted inside `max_w` x `max_h`, as tightly packed
/// RGBA8 (sRGB). Returns null on failure. Release with [`rl_buffer_free`].
///
/// # Safety
/// `session` from [`rl_session_new`]; `out_w`, `out_h`, `out_len` valid for writes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rl_render(session: *mut RlSession, id: u64, max_w: u32, max_h: u32, out_w: *mut u32, out_h: *mut u32, out_len: *mut usize) -> *mut u8 {
    unsafe { rl_render_hist(session, id, max_w, max_h, out_w, out_h, out_len, std::ptr::null_mut()) }
}

/// Like [`rl_render`], also writing the histogram of the result into `hist` (null to skip):
/// 4 x 256 `u32` bins in the order red, green, blue, luma.
///
/// # Safety
/// As [`rl_render`]; `hist`, when non-null, must have room for 1024 `u32`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rl_render_hist(
    session: *mut RlSession,
    id: u64,
    max_w: u32,
    max_h: u32,
    out_w: *mut u32,
    out_h: *mut u32,
    out_len: *mut usize,
    hist: *mut u32,
) -> *mut u8 {
    let Some(session) = (unsafe { session.as_mut() }) else { return std::ptr::null_mut() };
    let r = catch_unwind(AssertUnwindSafe(|| session.0.render_now(lightcraft_catalog::PhotoId(id), max_w as usize, max_h as usize)));
    let Ok(Ok(rendered)) = r else { return std::ptr::null_mut() };
    if !hist.is_null() {
        let h = &rendered.histogram;
        for (c, bins) in [&h.r, &h.g, &h.b, &h.luma].into_iter().enumerate() {
            for i in 0..256 {
                unsafe { *hist.add(c * 256 + i) = bins.get(i).copied().unwrap_or(0) };
            }
        }
    }
    let img = rendered.image;
    let bytes: Vec<u8> = img.data.iter().flatten().copied().collect();
    unsafe {
        *out_w = img.width as u32;
        *out_h = img.height as u32;
        *out_len = bytes.len();
    }
    Box::into_raw(bytes.into_boxed_slice()).cast::<u8>()
}

/// A render detached from the session: build it with [`rl_job_new`] (fast, needs the session),
/// run it with [`rl_job_run`] on any thread (slow, no session), hand it back with [`rl_job_finish`].
pub struct RlJob {
    job: Option<lightcraft_engine::RenderJob>,
    result: Option<lightcraft_engine::media::RenderResult>,
}

/// `kind`: 0 full-quality fit, 1 grid/filmstrip thumbnail (disk cached), 2 draft (interactive drags),
/// 3 full uncropped frame (shown while the crop tool is active).
/// Null when the photo does not exist.
///
/// # Safety
/// `session` from [`rl_session_new`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rl_job_new(session: *mut RlSession, id: u64, max_w: u32, max_h: u32, kind: i32) -> *mut RlJob {
    let Some(session) = (unsafe { session.as_mut() }) else { return std::ptr::null_mut() };
    let pid = lightcraft_catalog::PhotoId(id);
    let job = catch_unwind(AssertUnwindSafe(|| match kind {
        1 => session.0.thumb_job(pid, max_w.max(max_h) as usize),
        2 => session.0.render_job(pid, max_w as usize, max_h as usize, false, true).map(|j| j.draft()),
        3 => session.0.render_job(pid, max_w as usize, max_h as usize, false, false),
        _ => session.0.render_job(pid, max_w as usize, max_h as usize, false, true),
    }));
    match job {
        Ok(Some(job)) => Box::into_raw(Box::new(RlJob { job: Some(job), result: None })),
        _ => std::ptr::null_mut(),
    }
}

/// Like [`rl_job_new`] (kind 0 full, 2 draft) with the region of mask `mask_id` tinted rose over the
/// photo; `mask_id` 0 tints every visible mask. Null when the photo does not exist.
///
/// # Safety
/// `session` from [`rl_session_new`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rl_job_new_mask_overlay(session: *mut RlSession, id: u64, max_w: u32, max_h: u32, kind: i32, mask_id: u32) -> *mut RlJob {
    let Some(session) = (unsafe { session.as_mut() }) else { return std::ptr::null_mut() };
    let pid = lightcraft_catalog::PhotoId(id);
    let color = [242, 58, 92];
    let overlay = if mask_id == 0 {
        lightcraft_engine::pipeline::Overlay::AllMasks { view: lightcraft_engine::pipeline::MaskView::Color, color, opacity: 55 }
    } else {
        lightcraft_engine::pipeline::Overlay::Mask { id: mask_id as u16, view: lightcraft_engine::pipeline::MaskView::Color, color, opacity: 55 }
    };
    let job = catch_unwind(AssertUnwindSafe(|| {
        session.0.render_job(pid, max_w as usize, max_h as usize, false, kind != 3).map(|j| {
            let j = if kind == 2 { j.draft() } else { j };
            j.with_overlay(overlay)
        })
    }));
    match job {
        Ok(Some(job)) => Box::into_raw(Box::new(RlJob { job: Some(job), result: None })),
        _ => std::ptr::null_mut(),
    }
}

/// A render of photo `id` as if the look `preset_id` were applied (`amount` percent), without changing
/// the photo's edits: a live preview for a picker. Null when the photo or the look does not exist.
///
/// # Safety
/// `session` from [`rl_session_new`]; `preset_id` NUL-terminated.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rl_job_new_preset(session: *mut RlSession, id: u64, max_w: u32, max_h: u32, preset_id: *const c_char, amount: u32) -> *mut RlJob {
    let Some(session) = (unsafe { session.as_mut() }) else { return std::ptr::null_mut() };
    if preset_id.is_null() {
        return std::ptr::null_mut();
    }
    let Ok(preset) = unsafe { CStr::from_ptr(preset_id) }.to_str() else { return std::ptr::null_mut() };
    let pid = lightcraft_catalog::PhotoId(id);
    let job = catch_unwind(AssertUnwindSafe(|| session.0.preview_job_with_preset(pid, max_w as usize, max_h as usize, preset, f64::from(amount) / 100.0)));
    match job {
        Ok(Some(job)) => Box::into_raw(Box::new(RlJob { job: Some(job), result: None })),
        _ => std::ptr::null_mut(),
    }
}

/// Run the job; same outputs as [`rl_render_hist`]. Call once, on any thread.
///
/// # Safety
/// `job` from [`rl_job_new`], not shared across threads while this runs; out pointers valid.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rl_job_run(job: *mut RlJob, out_w: *mut u32, out_h: *mut u32, out_len: *mut usize, hist: *mut u32) -> *mut u8 {
    let Some(job) = (unsafe { job.as_mut() }) else { return std::ptr::null_mut() };
    let Some(j) = job.job.take() else { return std::ptr::null_mut() };
    let Ok(result) = catch_unwind(AssertUnwindSafe(|| j.run())) else { return std::ptr::null_mut() };
    let out = match &result.rendered {
        Ok(rendered) => {
            if !hist.is_null() {
                let h = &rendered.histogram;
                for (c, bins) in [&h.r, &h.g, &h.b, &h.luma].into_iter().enumerate() {
                    for i in 0..256 {
                        unsafe { *hist.add(c * 256 + i) = bins.get(i).copied().unwrap_or(0) };
                    }
                }
            }
            let img = &rendered.image;
            let bytes: Vec<u8> = img.data.iter().flatten().copied().collect();
            unsafe {
                *out_w = img.width as u32;
                *out_h = img.height as u32;
                *out_len = bytes.len();
            }
            Box::into_raw(bytes.into_boxed_slice()).cast::<u8>()
        }
        Err(_) => std::ptr::null_mut(),
    };
    job.result = Some(result);
    out
}

/// Give the finished job back to the session (it keeps the decoded source and thumbnail) and free it.
///
/// # Safety
/// `job` from [`rl_job_new`], freed once; `session` may be null (the job is just freed).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rl_job_finish(session: *mut RlSession, job: *mut RlJob) {
    if job.is_null() {
        return;
    }
    let job = unsafe { Box::from_raw(job) };
    if let (Some(session), Some(result)) = (unsafe { session.as_mut() }, job.result.as_ref()) {
        let _ = catch_unwind(AssertUnwindSafe(|| session.0.accept(result)));
    }
}

/// Swift's segmenter (Apple Vision): `(rgb, w, h, key, clicks [x, y, include]*, n_clicks, out_logits, side)`;
/// returns 1 = mask written, 0 = nothing to select, negative = failure.
type SegmentCb = unsafe extern "C" fn(*const u8, i32, i32, u64, *const f32, i32, *mut f32, i32) -> i32;
static SEGMENT_CB: std::sync::OnceLock<SegmentCb> = std::sync::OnceLock::new();
/// Side of the coverage grid Vision's mask is sampled to.
const VISION_SIDE: usize = 384;

fn vision_segment(rgb: &[u8], w: usize, h: usize, key: u64, clicks: &[[f32; 3]]) -> Result<Option<lightcraft_engine::segment::platform::PlatformMask>, String> {
    let cb = SEGMENT_CB.get().ok_or("Apple Vision segmentation is not available")?;
    if rgb.len() < w.saturating_mul(h).saturating_mul(3) || w == 0 || h == 0 {
        return Err("the photo could not be prepared for Apple Vision".into());
    }
    let mut logits = vec![0f32; VISION_SIDE * VISION_SIDE];
    // SAFETY: the buffers outlive the call and their sizes match what is passed (checked above).
    let r = unsafe { cb(rgb.as_ptr(), w as i32, h as i32, key, clicks.as_ptr().cast(), clicks.len() as i32, logits.as_mut_ptr(), VISION_SIDE as i32) };
    match r {
        1 => Ok(Some(lightcraft_engine::segment::platform::PlatformMask { side: VISION_SIDE, logits })),
        0 => Ok(None),
        -2 => Err("Apple Vision subject selection needs iOS 17 or later".into()),
        e => Err(format!("Apple Vision could not select anything ({e})")),
    }
}

/// Swift registers its Vision segmenter at launch; AI masks then need no model download.
#[unsafe(no_mangle)]
pub extern "C" fn rl_set_segmenter(cb: Option<SegmentCb>) {
    if let Some(cb) = cb
        && SEGMENT_CB.set(cb).is_ok()
    {
        lightcraft_engine::segment::platform::set_platform_segmenter(vision_segment);
    }
}

/// # Safety
/// `ptr`/`len` exactly as returned by [`rl_render`], freed once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rl_buffer_free(ptr: *mut u8, len: usize) {
    if !ptr.is_null() {
        // SAFETY: the buffer came from `Box<[u8]>::into_raw` with exactly `len` bytes.
        drop(unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(ptr, len)) });
    }
}

/// # Safety
/// `session` must come from [`rl_session_new`] and not be used afterwards.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rl_session_free(session: *mut RlSession) {
    if !session.is_null() {
        drop(unsafe { Box::from_raw(session) });
    }
}

/// # Safety
/// `s` must be a string returned by this library, freed once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rl_string_free(s: *mut c_char) {
    if !s.is_null() {
        drop(unsafe { CString::from_raw(s) });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn call(s: *mut RlSession, id: &str, params: &str) -> Value {
        let (id, params) = (CString::new(id).unwrap(), CString::new(params).unwrap());
        let r = unsafe { rl_execute(s, id.as_ptr(), params.as_ptr()) };
        let v = serde_json::from_str(unsafe { CStr::from_ptr(r) }.to_str().unwrap()).unwrap();
        unsafe { rl_string_free(r) };
        v
    }

    #[test]
    fn unknown_command_is_an_error_not_a_crash() {
        let s = rl_session_new(1);
        assert!(call(s, "no.such.command", "{}").get("error").is_some());
        assert!(call(s, "develop.set", "{not json").get("error").is_some());
        unsafe { rl_session_free(s) };
    }

    #[test]
    fn demo_photo_renders() {
        let s = rl_session_new(1);
        let ids = unsafe { rl_visible_ids(s) };
        let v: Value = serde_json::from_str(unsafe { CStr::from_ptr(ids) }.to_str().unwrap()).unwrap();
        unsafe { rl_string_free(ids) };
        let id = v["ok"][0].as_u64().expect("demo has photos");
        let (mut w, mut h, mut len) = (0u32, 0u32, 0usize);
        let p = unsafe { rl_render(s, id, 256, 256, &mut w, &mut h, &mut len) };
        assert!(!p.is_null() && w > 0 && h > 0 && len == (w * h * 4) as usize);
        unsafe { rl_buffer_free(p, len) };
        unsafe { rl_session_free(s) };
    }

    #[test]
    fn export_writes_a_jpeg() {
        let s = rl_session_new(1);
        let out = std::env::temp_dir().join(format!("rl-export-{}.jpg", std::process::id()));
        let params = format!(r#"{{"path":"{}","longEdge":300,"format":"jpeg","quality":80}}"#, out.display());
        let r = call(s, "app.export", &params);
        assert!(r.get("error").is_none(), "{r}");
        assert!(std::fs::metadata(&out).is_ok_and(|m| m.len() > 1000));
        let _ = std::fs::remove_file(&out);
        unsafe { rl_session_free(s) };
    }

    #[test]
    fn null_session_is_reported() {
        let id = CString::new("x").unwrap();
        let r = unsafe { rl_execute(std::ptr::null_mut(), id.as_ptr(), std::ptr::null()) };
        unsafe { rl_string_free(r) };
    }
}
