# LightCraft iPad port plan

## Workspace layout

The Cargo workspace is the root `Cargo.toml`: `crates/*`, `apps/*`, and `xtask`. Image data and codecs are in the lower-level crates (`geom`, `color`, `raster`, `raw`, `codecs`, `develop`, `pipeline`, `catalog`, `engine`). `crates/ui-egui` owns the shared egui application and controls. `apps/lightcraft` is the native desktop host, `apps/lightcraft-web` is the WASM browser host, and `xtask` builds/checks packaging. The repository instructions require that platform FFI stay out of the layered crates and that production code remain safe and non-panicking.

## Desktop window and event loop

`apps/lightcraft/src/main.rs` parses CLI/library preferences, creates the `Session`, selects a window renderer, and calls `eframe::run_native`. The closure receives the egui/wgpu context and constructs `LightcraftApp`; eframe owns the native window and event loop through winit. `NativeOptions` sets a 1600×1000 desktop viewport and platform-specific drag/drop/menu behavior. `window_gpu.rs` picks eframe's renderer and backend policy. This desktop host contains substantial OS-specific services and is not a direct iOS entry point.

## wgpu selection

The workspace pins wgpu 30 with `std`, `parking_lot`, `metal`, `vulkan`, `dx12`, and `wgsl`. `lightcraft-engine` selects compute backends from compiled/available backends and user preferences; `apps/lightcraft/src/window_gpu.rs` separately configures the egui window renderer through eframe's `egui_wgpu`. On iOS, Metal is the intended backend. CPU rendering is already a supported engine path; a native host must handle device/surface creation failure without enabling the GPU compute path. The current app's renderer fallback chain is desktop-oriented and must not be reused blindly on iOS.

## Web storage and import

The web host uses `apps/lightcraft-web/src/backend.rs`: OPFS is preferred, with IndexedDB as a fallback and an in-memory mode for temporary sessions. Catalog, UI preferences, view state, thumbnails and originals are stored in browser storage. The host requests persistent storage and provides backup/restore commands. File import uses an HTML file input and drag/drop, stores the bytes before importing, and exports through a browser download. See `docs/web.md` for the current storage and failure behavior.

## iPad risks and decisions

- **Memory:** RAW decoding and rendering can have a large transient footprint; iPad memory is shared with the OS and Safari/iPadOS may terminate large processes. Initial work should keep previews bounded and renders serialized; full-resolution export needs explicit allocation limits.
- **Touch and Pencil:** egui already consumes multi-touch zoom/translation in `crates/ui-egui/src/panels/detail.rs`, but touch is not a hover device and many desktop controls use compact sizing or hover affordances. Safari also needs touch gestures to reach the canvas. Pencil pressure requires host input plumbing and a verified egui event path.
- **File access:** Safari can import through its picker but browser persistence remains origin-scoped. A native app needs document/photo pickers and explicit sandbox copies.
- **Safe areas and windowing:** a PWA must respect `env(safe-area-inset-*)`; a native app needs safe-area-aware sizing. iPad split view and Stage Manager can continuously resize the canvas and panels, so fixed desktop minimum sizes are inappropriate.
- **Native build environment:** this checkout has Rust targets for `aarch64-apple-ios` and `aarch64-apple-ios-sim`, but the active developer directory is Command Line Tools and `/Applications` has no Xcode. `xcodebuild` currently exits because full Xcode is unavailable. Native build, simulator launch and screenshot verification therefore depend on Xcode becoming available.
- **Brand:** iPad fork name is “LightCraft iPad (fork)”; the intended reverse-DNS bundle identifier template is `com.<me>.lightcraftpad`. No ArtCraft marks or wordmark may be shipped. New app icons must be original.

## Work order

1. Make the web build installable and usable in iPad Safari; document secure LAN hosting and exact device checks.
2. Add the least invasive native iOS host scaffold that preserves the existing crate layering and can be built once Xcode is available.
3. Address shared egui touch affordances and memory limits where the implementation is verifiable in this checkout.
4. Record native verification gaps and exact handoff steps in `PROGRESS.md` and `RUN-ON-IPAD.md`.
