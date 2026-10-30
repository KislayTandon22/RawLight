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
    match catch_unwind(AssertUnwindSafe(|| session.0.execute(id, &params))) {
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
    let Some(session) = (unsafe { session.as_mut() }) else { return std::ptr::null_mut() };
    let r = catch_unwind(AssertUnwindSafe(|| session.0.render_now(lightcraft_catalog::PhotoId(id), max_w as usize, max_h as usize)));
    let Ok(Ok(rendered)) = r else { return std::ptr::null_mut() };
    let img = rendered.image;
    let mut bytes: Vec<u8> = img.data.iter().flatten().copied().collect();
    bytes.shrink_to_fit();
    unsafe {
        *out_w = img.width as u32;
        *out_h = img.height as u32;
        *out_len = bytes.len();
    }
    let mut bytes = std::mem::ManuallyDrop::new(bytes);
    bytes.as_mut_ptr()
}

/// # Safety
/// `ptr`/`len` exactly as returned by [`rl_render`], freed once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rl_buffer_free(ptr: *mut u8, len: usize) {
    if !ptr.is_null() {
        drop(unsafe { Vec::from_raw_parts(ptr, len, len) });
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
    fn null_session_is_reported() {
        let id = CString::new("x").unwrap();
        let r = unsafe { rl_execute(std::ptr::null_mut(), id.as_ptr(), std::ptr::null()) };
        unsafe { rl_string_free(r) };
    }
}
