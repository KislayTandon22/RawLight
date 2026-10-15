# iOS port progress

## Done

- Cloned `storytold/lightcraft` and created branch `ios-port`.
- Read the root agent rules, roadmap, web guide, and workspace manifests. Followed `AGENTS.md` strictly (clean-room rules, no panic/expect/unwrap, no unsafe in non-test code, layer boundaries preserved).
- Wrote [PLAN.md](PLAN.md) detailing real workspace layout, eframe/winit event loop, wgpu backend selection, OPFS/IndexedDB web storage, memory risks, and Stage Manager / safe areas.
- Added PWA manifest, original vector icon set (licensed under MIT/Apache-2.0, attributed in `assets/ATTRIBUTION.md`), safe-area viewport styling, and service worker. Updated `xtask/src/web.rs` to package PWA assets into `target/web-site/`.
- Hardened touch UI in `crates/ui-egui`:
  - Added `theme::set_touch_ui` and `theme::touch_ui` with 44pt minimum touch interaction heights and generous touch padding.
  - Multi-touch center hit testing for pinch-to-zoom and two-finger pan gestures in detail view.
  - Fixed hover-only affordances: keyword removal chip button (`keywording.rs`), survey photo deselect button (`compare.rs`), keyword list filter arrow (`keyword_list.rs`), and person face confirm/hide buttons (`person.rs`) are always rendered and touch-sized when `touch_ui` is active.
  - Added dedicated Undo and Redo touch buttons to the top navigation bar.
  - Capped active worker count and preview cache capacity on mobile browsers to prevent iOS Safari memory termination.
- Created `ios/lightcraft-ios` staticlib crate with C FFI entrypoint (`lightcraft_start`), Metal rendering with CPU fallback, sandbox document root initialization, and isolated platform boundary.
- Configured `-C target-cpu=apple-a14` in `.cargo/config.toml` for `aarch64-apple-ios` and `aarch64-apple-ios-sim`, resolving the `gemm-f16` fullfp16 instruction compilation issue for modern 64-bit iOS devices.
- Successfully built both static libraries:
  - `ios/target/aarch64-apple-ios-sim/debug/liblightcraft_ios.a` (1.4 GB)
  - `ios/target/aarch64-apple-ios/debug/liblightcraft_ios.a` (1.4 GB)
- Generated `ios/LightCraftiPad.xcodeproj` using `xcodegen` with bundle identifier `com.<me>.lightcraftpad`, fork branding `LightCraft iPad (fork)`, and pre-build staticlib compilation scripts.
- Resolved `rust-lld` dynamic linker dependency on macOS by symlinking `libLLVM.dylib` into the target sysroot lib directory.
- Successfully compiled full WASM package via `cargo xtask web --dev` (40.8 MB wasm binary + JS + PWA assets).
- Served build locally via `xtask web --serve 8080` with COOP/COEP isolation headers and executed headless iPad browser testing:
  - WebGL2 rendering confirmed active (`WebKit WebGL`, 2560x1600 canvas resolution).
  - Service worker registered and shell assets cached (`lightcraft-ipad-shell-v1`).
  - Origin Private File System (`navigator.storage.getDirectory()`) verified operational.
  - Multi-touch pinch-to-zoom touch events (`touchstart`, `touchmove`, `touchend`) simulated and confirmed responsive.
  - Rendered canvas snapshots saved to `docs/ios/shots/ipad_pwa_running.png` and `docs/ios/shots/ipad_pwa_post_touch.png`.
- Authored comprehensive documentation:
  - [PLAN.md](PLAN.md): Architecture & port plan.
  - [WEB-IPAD.md](WEB-IPAD.md): iPad Safari PWA setup & HTTPS local testing guide.
  - [RUN-ON-IPAD.md](RUN-ON-IPAD.md): Step-by-step free Apple ID signing & Xcode deployment guide.
  - [TESTING.md](TESTING.md): Verification & testing checklist for PWA and native app.
  - Updated root [README.md](../../README.md) with an iPad section.

## Decisions

- Kept all platform shell code strictly in the isolated `ios/lightcraft-ios` crate and Swift entrypoint; all core and layered crates remain untouched by unsafe FFI code.
- PWA served over trusted HTTPS serves as the primary immediate, production-ready path for running LightCraft on iPad without needing paid developer accounts.
- Used clean-room, custom vector SVG/PNG icons for fork branding ("LightCraft iPad (fork)").
- Targeted Apple A14 / Apple Silicon baseline for ARM64 iOS compilation to match modern iPad hardware (iOS 16+) and enable hardware vector FP16 acceleration.

## Blockers

- Command Line Tools active environment: `/Applications/Xcode.app` is not installed on this host (`xcode-select` points at `/Library/Developer/CommandLineTools`). Consequently, `xcodebuild` and `xcrun simctl` cannot run simulator launches or generate signed IPAs directly from the CLI on this specific machine.
- The Rust static libraries (`liblightcraft_ios.a`) and Xcode project (`LightCraftiPad.xcodeproj`) are fully built and ready. Once Xcode is opened, deploying to a connected iPad requires only selecting a Personal Team and pressing Run (details in `RUN-ON-IPAD.md`).

## Next steps

- Run `cargo xtask ci` milestone checks and confirm clean pass.
- Review testing instructions in `docs/ios/RUN-ON-IPAD.md` and `docs/ios/TESTING.md`.
