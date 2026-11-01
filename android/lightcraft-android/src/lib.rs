//! RawLight for Android: eframe host around the LightCraft engine and its touch UI.
#![deny(clippy::unwrap_used, clippy::expect_used, clippy::panic, clippy::unimplemented, clippy::todo, clippy::unreachable)]

use std::path::PathBuf;

use eframe::egui::{Context, RawInput, Ui};
use lightcraft_engine::Session;
use lightcraft_ui_egui::{LightcraftApp, Services};

struct AndroidHost {
    app: LightcraftApp,
}

impl eframe::App for AndroidHost {
    fn logic(&mut self, ctx: &Context, _frame: &mut eframe::Frame) {
        // winit has no safe-area query on Android yet: status bar on top, gesture bar below
        lightcraft_ui_egui::theme::set_safe_area_insets(ctx, 32.0, 24.0, 0.0, 0.0);
        self.app.logic(ctx);
    }

    fn raw_input_hook(&mut self, ctx: &Context, raw: &mut RawInput) {
        self.app.raw_input_hook(ctx, raw);
    }

    fn ui(&mut self, ui: &mut Ui, _frame: &mut eframe::Frame) {
        self.app.ui(ui);
    }

    fn on_exit(&mut self) {
        if let Err(error) = self.app.session.close_library() {
            log::error!("saving the library failed: {error}");
        }
        if !self.app.shutdown(std::time::Duration::from_secs(2)) {
            log::warn!("shutdown ended while render work was still active");
        }
    }
}

fn create_services() -> Services {
    let mut services = Services {
        write: Some(Box::new(lightcraft_engine::export::write_file)),
        write_shared: Some(std::sync::Arc::new(lightcraft_engine::export::write_file)),
        ..Services::default()
    };
    services.png = Some(Box::new(|img: &lightcraft_raster::Rgba8| {
        lightcraft_codecs::encode_png(&lightcraft_codecs::EncodeImage::rgba8(img), &lightcraft_codecs::EncodeMeta::default()).unwrap_or_default()
    }));
    services
}

/// True on the Android emulator (goldfish / ranchu expose a qemu pipe device).
fn is_emulator() -> bool {
    ["/dev/goldfish_pipe", "/dev/qemu_pipe"].iter().any(|p| std::path::Path::new(p).exists())
}

fn launch(app: winit::platform::android::activity::AndroidApp) {
    let base = app.internal_data_path().unwrap_or_else(|| PathBuf::from("/data/local/tmp"));
    let library_dir = base.join("LightCraft Library");
    log::info!("RawLight library dir: {library_dir:?}");

    lightcraft_engine::gpu::set_enabled(true);
    lightcraft_engine::gpu::warm_up();

    let mut session = Session::new().with_fs().with_default_denoise_models().with_system_clock();
    let library_error = session.open_library(&library_dir, false).err().map(|e| e.to_string());
    session.media.preview_capacity = 2;

    let exports_dir = base.join("Exports");
    if let Err(e) = std::fs::create_dir_all(&exports_dir) {
        log::warn!("could not create {exports_dir:?}: {e}");
    }
    if session.last_export.is_none() {
        session.last_export = Some(serde_json::json!({"dir": exports_dir.to_string_lossy(), "format": "jpeg", "quality": 90}));
    }

    let mut wgpu_options = eframe::egui_wgpu::WgpuConfiguration::default();
    if let eframe::egui_wgpu::WgpuSetup::CreateNew(ref mut setup) = wgpu_options.wgpu_setup {
        if is_emulator() {
            // the emulator's software Vulkan takes the whole emulator down; its GLES path is stable
            log::info!("emulator detected: wgpu uses GLES");
            setup.instance_descriptor.backends = eframe::wgpu::Backends::GL;
        }
        setup.device_descriptor = std::sync::Arc::new(|adapter| {
            let supported = adapter.limits();
            let mut limits = eframe::wgpu::Limits::downlevel_webgl2_defaults();
            limits.max_texture_dimension_2d = 8192.min(supported.max_texture_dimension_2d);
            limits.max_inter_stage_shader_variables = supported.max_inter_stage_shader_variables;
            eframe::wgpu::DeviceDescriptor { label: Some("egui wgpu device"), required_limits: limits, ..Default::default() }
        });
    }
    let options = eframe::NativeOptions { android_app: Some(app), renderer: eframe::Renderer::Wgpu, wgpu_options, ..Default::default() };

    let result = eframe::run_native(
        "RawLight",
        options,
        Box::new(move |cc| {
            lightcraft_ui_egui::theme::set_touch_ui(&cc.egui_ctx, true);
            lightcraft_ui_egui::theme::set_safe_area_insets(&cc.egui_ctx, 32.0, 24.0, 0.0, 0.0);
            let mut app = LightcraftApp::new(session, create_services());
            app.ui.settings.dark_theme = lightcraft_ui_egui::state::DarkTheme::Glass;
            app.ui.right_width = 340.0;
            app.ui.left_width = 300.0;
            app.ui.dialog = None;
            if let Some(error) = &library_error {
                app.toast_for(&cc.egui_ctx, format!("Your library could not be opened ({error}). Photos you add now are not saved."), 12.0);
            }
            Ok(Box::new(AndroidHost { app }))
        }),
    );
    if let Err(e) = result {
        log::error!("run_native failed: {e}");
    }
}

#[cfg(target_os = "android")]
#[unsafe(no_mangle)]
fn android_main(app: winit::platform::android::activity::AndroidApp) {
    android_logger::init_once(android_logger::Config::default().with_max_level(log::LevelFilter::Info).with_tag("RawLight"));
    std::panic::set_hook(Box::new(|info| log::error!("panic: {info}")));
    launch(app);
}
