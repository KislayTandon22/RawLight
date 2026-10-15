//! Minimal iOS host shell. The unsafe C-string read is isolated here; the layered crates remain safe.
#![deny(clippy::unwrap_used, clippy::expect_used, clippy::panic, clippy::unimplemented, clippy::todo, clippy::unreachable)]

use std::ffi::{CStr, c_char};
use std::path::PathBuf;

use egui::{Context, Ui};
use lightcraft_engine::Session;
use lightcraft_ui_egui::{LightcraftApp, Services};

struct IosApp(LightcraftApp);

impl eframe::App for IosApp {
    fn logic(&mut self, ctx: &Context, _frame: &mut eframe::Frame) {
        self.0.logic(ctx);
    }

    fn ui(&mut self, ui: &mut Ui, _frame: &mut eframe::Frame) {
        self.0.ui(ui);
    }

    fn on_exit(&mut self) {
        if let Err(error) = self.0.session.close_library() {
            log::error!("saving the iOS library failed: {error}");
        }
        if !self.0.shutdown(std::time::Duration::from_secs(2)) {
            log::warn!("iOS shutdown ended while render work was still active");
        }
    }
}

fn launch(library_dir: PathBuf) -> i32 {
    lightcraft_engine::gpu::set_enabled(true);
    if !lightcraft_engine::gpu::available() {
        log::warn!("Metal compute initialization failed; using the CPU render path");
        lightcraft_engine::gpu::set_enabled(false);
    }

    let mut session = Session::new().with_fs().with_default_denoise_models().with_system_clock();
    let library_error = session.open_library(&library_dir, true).err().map(|error| error.to_string());
    if library_error.is_some() {
        session = Session::with_demo();
    }
    session.media.preview_capacity = 2;

    let result = eframe::run_native(
        "LightCraft iPad (fork)",
        eframe::NativeOptions { renderer: eframe::Renderer::Wgpu, ..Default::default() },
        Box::new(move |cc| {
            lightcraft_ui_egui::theme::set_touch_ui(&cc.egui_ctx, true);
            let mut app = LightcraftApp::new(session, Services::default());
            if let Some(error) = library_error {
                app.notices.push(format!("The app library could not be opened: {error}. This session is temporary."));
            }
            Ok(Box::new(IosApp(app)))
        }),
    );
    match result {
        Ok(()) => 0,
        Err(error) => {
            eprintln!("LightCraft iPad could not start: {error}");
            1
        }
    }
}

/// Starts winit's iOS event loop and opens the app's sandbox library directory.
///
/// # Safety boundary
/// Swift calls this with a live, NUL-terminated UTF-8 path for the duration of the call.
#[unsafe(no_mangle)]
pub extern "C" fn lightcraft_start(library_dir: *const c_char) -> i32 {
    if library_dir.is_null() {
        return 2;
    }
    // SAFETY: the Swift entry point passes `String.withCString`, so the pointer is non-null,
    // NUL-terminated, valid UTF-8, and remains alive until this synchronous call returns.
    let path = unsafe { CStr::from_ptr(library_dir) };
    let Ok(path) = path.to_str() else { return 2 };
    match std::panic::catch_unwind(|| launch(PathBuf::from(path))) {
        Ok(code) => code,
        Err(_) => {
            eprintln!("LightCraft iPad stopped after an unexpected startup failure");
            3
        }
    }
}
