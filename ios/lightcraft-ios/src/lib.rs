use std::ffi::{CStr, CString, c_char, c_void};
use std::path::PathBuf;
use std::sync::mpsc::{Sender, channel};

use eframe::egui::{Context, Ui};
use lightcraft_engine::Session;
use lightcraft_ui_egui::{LightcraftApp, Services};

unsafe extern "C" {
    fn ios_log(format: *const c_char);
    fn ios_open_url(url: *const c_char) -> bool;
    fn ios_share_file(path: *const c_char) -> bool;
    #[allow(dead_code)]
    fn ios_share_files(paths_json: *const c_char) -> bool;
    fn ios_show_native_picker(
        kind: u32,
        title: *const c_char,
        filter_name: *const c_char,
        filter_exts: *const c_char,
        file_name: *const c_char,
        context: *mut c_void,
        completion: unsafe extern "C" fn(*mut c_void, *const c_char),
    );
}

struct PickerCallbackPayload {
    tx: Sender<Vec<String>>,
    ctx: Context,
}

unsafe extern "C" fn on_picker_complete(ctx: *mut c_void, json_ptr: *const c_char) {
    if ctx.is_null() {
        return;
    }
    // SAFETY: ctx was created via Box::into_raw from a Box<PickerCallbackPayload>
    let payload = unsafe { Box::from_raw(ctx as *mut PickerCallbackPayload) };
    let mut paths = Vec::new();
    if !json_ptr.is_null() {
        // SAFETY: json_ptr is a valid NUL-terminated C string created by Swift
        let s = unsafe { CStr::from_ptr(json_ptr) };
        if let Ok(s) = s.to_str()
            && let Ok(parsed) = serde_json::from_str::<Vec<String>>(s)
        {
            paths = parsed;
        }
    }
    let _ = payload.tx.send(paths);
    payload.ctx.request_repaint();
}

struct OsLogger;

impl log::Log for OsLogger {
    fn enabled(&self, metadata: &log::Metadata) -> bool {
        metadata.level() <= log::Level::Info
    }

    fn log(&self, record: &log::Record) {
        if !self.enabled(record.metadata()) {
            return;
        }
        let msg = format!("[LightCraft-Rust] [{}] {}\0", record.level(), record.args());
        unsafe {
            ios_log(msg.as_ptr() as *const c_char);
        }
    }

    fn flush(&self) {}
}

static OS_LOGGER: OsLogger = OsLogger;

struct IosApp {
    app: LightcraftApp,
    first_frame: bool,
}

impl eframe::App for IosApp {
    fn logic(&mut self, ctx: &Context, _frame: &mut eframe::Frame) {
        if self.first_frame {
            log::info!("[LightCraft] First logic frame rendering!");
        }
        self.app.logic(ctx);
    }

    fn ui(&mut self, ui: &mut Ui, _frame: &mut eframe::Frame) {
        if self.first_frame {
            log::info!("[LightCraft] First UI frame rendering!");
            self.first_frame = false;
        }
        self.app.ui(ui);
    }

    fn on_exit(&mut self) {
        log::info!("[LightCraft] on_exit callback invoked!");
        if let Err(error) = self.app.session.close_library() {
            log::error!("saving the iOS library failed: {error}");
        }
        if !self.app.shutdown(std::time::Duration::from_secs(2)) {
            log::warn!("iOS shutdown ended while render work was still active");
        }
    }
}

fn create_services(egui_ctx: Context) -> Services {
    let mut services = Services::default();

    // Atomic file writing services for export batch and presets
    services.write = Some(Box::new(lightcraft_engine::export::write_file));
    services.write_shared = Some(std::sync::Arc::new(lightcraft_engine::export::write_file));
    services.png = Some(Box::new(|img: &lightcraft_raster::Rgba8| {
        lightcraft_codecs::encode_png(&lightcraft_codecs::EncodeImage::rgba8(img), &lightcraft_codecs::EncodeMeta::default()).unwrap_or_default()
    }));

    // Native iOS Share Sheet for exported photos and files
    services.reveal = Some(Box::new(|path: &str| {
        let c_path = CString::new(path).map_err(|e| e.to_string())?;
        let ok = unsafe { ios_share_file(c_path.as_ptr()) };
        if ok { Ok(()) } else { Err(format!("failed to open share sheet for {path}")) }
    }));

    // Asynchronous non-blocking native picker for egui's pick::poll (#191)
    let picker_ctx = egui_ctx.clone();
    services.picker = Some(Box::new(move |req: lightcraft_ui_egui::pick::PickRequest| {
        let (tx, rx) = channel();
        let payload = Box::new(PickerCallbackPayload { tx, ctx: picker_ctx.clone() });
        let ctx_ptr = Box::into_raw(payload) as *mut c_void;
        let kind = match req.kind {
            lightcraft_ui_egui::pick::PickKind::Files => 0,
            lightcraft_ui_egui::pick::PickKind::File => 1,
            lightcraft_ui_egui::pick::PickKind::Folder => 2,
            lightcraft_ui_egui::pick::PickKind::Save => 3,
        };

        let title_c = req.title.as_ref().map(|s| CString::new(s.as_str()).unwrap_or_default());
        let title_ptr = title_c.as_ref().map_or(std::ptr::null(), |c| c.as_ptr());

        let filter_name_c = req.filter.as_ref().map(|(n, _)| CString::new(n.as_str()).unwrap_or_default());
        let filter_name_ptr = filter_name_c.as_ref().map_or(std::ptr::null(), |c| c.as_ptr());

        let filter_exts_joined = req.filter.as_ref().map(|(_, exts)| exts.join(","));
        let filter_exts_c = filter_exts_joined.as_ref().map(|s| CString::new(s.as_str()).unwrap_or_default());
        let filter_exts_ptr = filter_exts_c.as_ref().map_or(std::ptr::null(), |c| c.as_ptr());

        let file_name_c = req.file_name.as_ref().map(|s| CString::new(s.as_str()).unwrap_or_default());
        let file_name_ptr = file_name_c.as_ref().map_or(std::ptr::null(), |c| c.as_ptr());

        unsafe {
            ios_show_native_picker(kind, title_ptr, filter_name_ptr, filter_exts_ptr, file_name_ptr, ctx_ptr, on_picker_complete);
        }
        Ok(rx)
    }));

    // Lightroom Classic catalog import picker (.lrcat)
    let lr_ctx = egui_ctx.clone();
    services.pick_lightroom_catalog = Some(Box::new(move || {
        let (tx, rx) = channel();
        let payload = Box::new(PickerCallbackPayload { tx, ctx: lr_ctx.clone() });
        let ctx_ptr = Box::into_raw(payload) as *mut c_void;
        let title = CString::new("Import Lightroom Catalog").unwrap_or_default();
        let filter_name = CString::new("Lightroom Classic Catalog").unwrap_or_default();
        let filter_exts = CString::new("lrcat").unwrap_or_default();
        unsafe {
            ios_show_native_picker(
                1, // kind: File
                title.as_ptr(),
                filter_name.as_ptr(),
                filter_exts.as_ptr(),
                std::ptr::null(),
                ctx_ptr,
                on_picker_complete,
            );
        }
        rx.recv().ok().and_then(|mut paths| paths.pop())
    }));

    // Synchronous fallback pickers
    let repaint_files = egui_ctx.clone();
    services.pick_files = Some(Box::new(move || {
        let (tx, rx) = channel();
        let payload = Box::new(PickerCallbackPayload { tx, ctx: repaint_files.clone() });
        let ctx_ptr = Box::into_raw(payload) as *mut c_void;
        unsafe {
            ios_show_native_picker(
                0, // kind: Files
                std::ptr::null(),
                std::ptr::null(),
                std::ptr::null(),
                std::ptr::null(),
                ctx_ptr,
                on_picker_complete,
            );
        }
        rx.recv().ok().unwrap_or_default()
    }));

    let repaint_folder = egui_ctx.clone();
    services.pick_folder = Some(Box::new(move || {
        let (tx, rx) = channel();
        let payload = Box::new(PickerCallbackPayload { tx, ctx: repaint_folder.clone() });
        let ctx_ptr = Box::into_raw(payload) as *mut c_void;
        unsafe {
            ios_show_native_picker(
                2, // kind: Folder
                std::ptr::null(),
                std::ptr::null(),
                std::ptr::null(),
                std::ptr::null(),
                ctx_ptr,
                on_picker_complete,
            );
        }
        rx.recv().ok().and_then(|mut paths| paths.pop())
    }));

    // Preset export picker (kind: Save)
    let save_preset_ctx = egui_ctx.clone();
    services.save_preset_file = Some(Box::new(move |name: &str| {
        let (tx, rx) = channel();
        let payload = Box::new(PickerCallbackPayload { tx, ctx: save_preset_ctx.clone() });
        let ctx_ptr = Box::into_raw(payload) as *mut c_void;
        let title = CString::new("Export Preset").unwrap_or_default();
        let filter_name = CString::new("LightCraft Preset").unwrap_or_default();
        let filter_exts = CString::new("lcpreset").unwrap_or_default();
        let file_name = CString::new(name).unwrap_or_default();
        unsafe {
            ios_show_native_picker(
                3, // kind: Save
                title.as_ptr(),
                filter_name.as_ptr(),
                filter_exts.as_ptr(),
                file_name.as_ptr(),
                ctx_ptr,
                on_picker_complete,
            );
        }
        rx.recv().ok().and_then(|mut paths| paths.pop())
    }));

    // System web URL opener for documentation / links
    services.open_url = Some(Box::new(|url: &str| {
        if !url.starts_with("https://") {
            return Err("only https links are opened".into());
        }
        let url_c = CString::new(url).map_err(|e| e.to_string())?;
        let ok = unsafe { ios_open_url(url_c.as_ptr()) };
        if ok { Ok(()) } else { Err(format!("failed to open URL: {url}")) }
    }));

    services
}

fn launch(library_dir: PathBuf) -> i32 {
    let _ = log::set_logger(&OS_LOGGER);
    log::set_max_level(log::LevelFilter::Info);
    log::info!("LightCraft launch initiated with library_dir: {:?}", library_dir);

    lightcraft_engine::gpu::set_enabled(true);
    // Warm up GPU pipeline on a background thread so UI starts immediately without blocking
    lightcraft_engine::gpu::warm_up();

    let mut session = Session::new().with_fs().with_default_denoise_models().with_system_clock();
    let library_error = session.open_library(&library_dir, true).err().map(|error| error.to_string());
    if library_error.is_some() {
        session = Session::with_demo();
    }
    session.media.preview_capacity = 2;

    // Default export directory inside iPad Documents/Exports container
    let exports_dir = library_dir.parent().unwrap_or(&library_dir).join("Exports");
    if let Err(e) = std::fs::create_dir_all(&exports_dir) {
        log::warn!("Could not create exports directory {:?}: {e}", exports_dir);
    }
    if session.last_export.is_none() {
        session.last_export = Some(serde_json::json!({
            "dir": exports_dir.to_string_lossy().to_string(),
            "format": "jpeg",
            "quality": 90,
        }));
    }

    let mut wgpu_options = eframe::egui_wgpu::WgpuConfiguration::default();
    if let eframe::egui_wgpu::WgpuSetup::CreateNew(ref mut setup) = wgpu_options.wgpu_setup {
        setup.device_descriptor = std::sync::Arc::new(|adapter| {
            let supported = adapter.limits();
            let mut limits = eframe::wgpu::Limits::downlevel_webgl2_defaults();
            limits.max_texture_dimension_2d = 8192.min(supported.max_texture_dimension_2d);
            limits.max_inter_stage_shader_variables = supported.max_inter_stage_shader_variables;
            eframe::wgpu::DeviceDescriptor { label: Some("egui wgpu device"), required_limits: limits, ..Default::default() }
        });
    }

    let native_options = eframe::NativeOptions { renderer: eframe::Renderer::Wgpu, wgpu_options, ..Default::default() };

    log::info!("Calling eframe::run_native...");
    let result = eframe::run_native(
        "LightCraft iPad (fork)",
        native_options,
        Box::new(move |cc| {
            log::info!("app_creator invoked: touch UI configured");
            lightcraft_ui_egui::theme::set_touch_ui(&cc.egui_ctx, true);
            let services = create_services(cc.egui_ctx.clone());
            let app = LightcraftApp::new(session, services);
            Ok(Box::new(IosApp { app, first_frame: true }))
        }),
    );

    match result {
        Ok(()) => {
            log::info!("eframe::run_native exited cleanly (0)");
            0
        }
        Err(e) => {
            log::error!("eframe::run_native failed: {e}");
            -1
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn lightcraft_start(library_dir: *const c_char) -> i32 {
    let path = if library_dir.is_null() {
        PathBuf::from("LightCraft Library")
    } else {
        let c_str = unsafe { CStr::from_ptr(library_dir) };
        c_str.to_str().map(PathBuf::from).unwrap_or_else(|_| PathBuf::from("LightCraft Library"))
    };
    launch(path)
}
