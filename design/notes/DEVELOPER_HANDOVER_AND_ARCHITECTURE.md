# LightCraft iPadOS & Multi-Platform: Developer Handover & System Architecture Guide

**Project:** LightCraft Photo Studio  
**Primary Target Platform:** iPadOS 17.0+ (Tested & Verified on Apple iPad Air 11-inch M4)  
**Hardware ID / UDID:** `00008132-000214443620C01C`  
**Native Retina Resolution:** 2360 × 1640 px (1180 × 820 pt @ 2.0x scale)  
**Repository Location:** `/Users/kislayranjanneetandon/Documents/Lightworks Ipad/lightcraft`  
**Desktop Handover Folder:** `/Users/kislayranjanneetandon/Desktop/Lightcraft_iPad_Audit_And_Skills`  
**Date of Handover:** October 2026  

---

## 1. Executive Summary & Handover Overview

LightCraft is a professional-grade, non-destructive photo editing studio built with a high-performance **Rust engine** and a modern, GPU-accelerated **Apple Liquid Glass** UI. It runs across multiple platforms, with primary focus on a native, touch-first experience for **iPadOS (Apple Silicon M-Series & A-Series)**, alongside **macOS Desktop**, **CLI**, and **WebAssembly**.

This document serves as the **definitive developer handover guide**. It catalogs every application and executable target in the repository, maps out all source file locations, details the end-to-end data flow between Swift/UIKit and Rust/Metal, and provides exact commands to build, test, and deploy the entire system.

---

## 2. Catalog of All Applications & Targets in the Monorepo

The repository contains **6 distinct application targets** and **31 modular Rust crates**:

```
                                  ┌────────────────────────────────────────────────────────┐
                                  │               LightCraft Monorepo Targets              │
                                  └────────────────────────────────────────────────────────┘
                                      │                  │                  │
                ┌─────────────────────┴───────┐   ┌──────┴──────┐    ┌──────┴─────────────────────┐
                │        Mobile / iPadOS      │   │   Desktop   │    │      Web / Headless        │
                ├─────────────────────────────┤   ├─────────────┤    ├────────────────────────────┤
                │ 1. LightCraft iPad App      │   │ 3. Desktop  │    │ 4. CLI & MCP Server        │
                │ 2. iOS C-FFI Bridge Lib     │   │    App      │    │ 5. WebAssembly (WASM) App  │
                │                             │   │             │    │ 6. SAM 3 Background Worker │
                └─────────────────────────────┘   └─────────────┘    └────────────────────────────┘
```

### 1. LightCraft iPad Native App (`LightCraft iPad (fork).app`)
* **Project File:** `ios/LightCraftiPad.xcodeproj`
* **Source Location:** `ios/LightCraft/`
* **Key Files:**
  * `ios/LightCraft/main.swift`: Standard iOS entry point.
  * `ios/LightCraft/SceneDelegate.swift`: Window lifecycle, `CAMetalLayer` setup, multi-window, and safe-area constraints.
  * `ios/LightCraft/PhotoPickerBridge.swift`: Manages the `MTKView` / `CAMetalLayer`, translates UIKit touch events into C-FFI calls, and presents the native iOS `PHPickerViewController` for zero-friction photo imports.
  * `ios/LightCraft/Info.plist`: App bundle configuration, privacy permissions (`NSPhotoLibraryUsageDescription`), orientations, and bundle ID `com.kislay.lightcraftpad`.
* **Role:** The production iPadOS app. Renders the Rust UI at full 120Hz ProMotion directly via Apple Metal API.

### 2. iOS C-FFI Static Bridge (`liblightcraft_ios.a`)
* **Source Location:** `ios/lightcraft-ios/`
* **Key Files:**
  * `ios/lightcraft-ios/src/lib.rs`: Exports C-compatible functions (`lightcraft_ios_init`, `lightcraft_ios_render_frame`, `lightcraft_ios_send_touch`, `lightcraft_ios_import_paths`, `lightcraft_ios_get_state`, `lightcraft_ios_shutdown`).
  * `ios/lightcraft-ios/src/monkey.rs`: Automated touch monkey testing for stress testing touch interactions and memory stability.
  * `ios/lightcraft-ios/tests/ios_bridge_test.rs`: 25 integration tests validating touch injection, view state transitions, and canvas panning.
* **Role:** Compiles as a `staticlib` for `aarch64-apple-ios` and links directly into Xcode.

### 3. LightCraft Desktop Application (`lightcraft`)
* **Manifest:** `apps/lightcraft/Cargo.toml`
* **Source Location:** `apps/lightcraft/src/main.rs`
* **Role:** The native desktop application for macOS (Intel & Apple Silicon), Windows, and Linux. Built on `eframe` (egui native platform wrapper), featuring multi-window menus, keyboard shortcuts, and native OS file dialogs.

### 4. LightCraft CLI & MCP Server (`lightcraft-cli`)
* **Manifest:** `apps/lightcraft-cli/Cargo.toml`
* **Source Location:** `apps/lightcraft-cli/src/main.rs`
* **Role:** Headless command-line utility. Performs batch photo rendering without launching a window, inspects catalogs, and hosts the **Model Context Protocol (MCP)** server over stdio for AI agent automation.

### 5. LightCraft WebAssembly Application (`lightcraft-web`)
* **Manifest:** `apps/lightcraft-web/Cargo.toml`
* **Source Location:** `apps/lightcraft-web/src/lib.rs`
* **Role:** Compiles the entire egui UI and photo pipeline to WebAssembly (`wasm32-unknown-unknown`), enabling in-browser zero-install editing via WebGL/WebGPU. Built via `cargo xtask web`.

### 6. SAM 3 Background AI Worker (`lightcraft-sam3-worker`)
* **Manifest:** `crates/segment/Cargo.toml`
* **Source Location:** `crates/segment/src/bin/lightcraft-sam3-worker.rs`
* **Role:** Standalone background daemon for running heavy SAM-3 AI segmentation models out-of-process, communicating via IPC channels to prevent UI frame hitches.

---

## 3. Layered Workspace Architecture (L0 to L5)

The Rust codebase strictly adheres to a **6-layer dependency architecture**:

```
Layer 5 (Applications & Frontends):  [lightcraft-ui-egui]  [lightcraft-mcp]  [apps/*]
                                            │
Layer 4 (Orchestration & State):     [lightcraft-engine]
                                            │
Layer 3 (Services & Storage):        [lightcraft-catalog] [lightcraft-gpu] [lightcraft-preview] [lightcraft-segment]
                                            │
Layer 2 (Image Processing):          [lightcraft-pipeline] [lightcraft-lensdb]
                                            │
Layer 1 (Domain Models & Formats):   [lightcraft-develop] [lightcraft-raw] [lightcraft-meta] [lightcraft-codecs]
                                            │
Layer 0 (Foundations):               [lightcraft-color] [lightcraft-geom] [lightcraft-raster] [lightcraft-sysmem]
```

### Complete Crate Map

| Crate Name | Layer | Directory Location | Primary Responsibility |
| :--- | :---: | :--- | :--- |
| `lightcraft-color` | L0 | `crates/color/` | Color spaces (sRGB, Display P3, Rec.2020, ACES), transfer curves, white balance math |
| `lightcraft-geom` | L0 | `crates/geom/` | Normalized points, rectangles, affine transforms, bezier curves, polygon clipping |
| `lightcraft-raster` | L0 | `crates/raster/` | Fast SIMD box blur, gaussian blur, resampling, bilinear/bicubic interpolators |
| `lightcraft-sysmem` | L0 | `crates/sysmem/` | System memory cleanup: returns freed heap memory to macOS/iOS kernel |
| `lightcraft-tiff` | L0 | `crates/tiff/` | Fast zero-copy TIFF / BigTIFF / DNG IFD parser and writer |
| `lightcraft-fetch` | L0 | `crates/fetch/` | Pure Rust HTTPS downloader with mirror failover, resume, and SHA-256 verification |
| `lightcraft-develop` | L1 | `crates/develop/` | Non-destructive edit model, Tone, Curves, Color Mixer, Mask specifications |
| `lightcraft-codecs` | L1 | `crates/codecs/` | Image container sniffing, JPEG, PNG, WebP, AVIF decoders and linear encoders |
| `lightcraft-raw` | L1 | `crates/raw/` | Camera RAW decoder, Bayer demosaicing (AHD, AMAZE), DNG color profiles |
| `lightcraft-meta` | L1 | `crates/meta/` | EXIF, XMP, and IPTC metadata extraction and embedding |
| `lightcraft-heif` | L1 | `crates/heif/` | Apple HEIC / HEIF still photo decoding with ICC profile matching |
| `lightcraft-inpaint` | L1 | `crates/inpaint/` | PatchMatch content-aware fill and membrane hole filling for spot removal |
| `lightcraft-geocode` | L1 | `crates/geocode/` | Offline reverse geocoding: GPS coordinates to City/State/Country via GeoNames |
| `lightcraft-scenes` | L1 | `crates/scenes/` | Synthetic HDR test scenes (Rec.2020 linear float) for automated validation |
| `lightcraft-faces` | L1 | `crates/faces/` | On-device face detection and facial feature bounding box localization |
| `lightcraft-denoise-core` | L1 | `crates/denoise-core/` | AI Denoise metadata, Bayer tiling, overlapping blend weight matrices |
| `lightcraft-denoise` | L1 | `crates/denoise/` | Pure-Rust CPU and ONNX inference for AI raw noise reduction |
| `lightcraft-pipeline` | L2 | `crates/pipeline/` | High-precision 32-bit float CPU develop pipeline and mathematical mask renderers |
| `lightcraft-lensdb` | L2 | `crates/lensdb/` | Lens database loader (Lensfun format), optical distortion & vignetting correction |
| `lightcraft-catalog` | L3 | `crates/catalog/` | SQLite / binary op-log catalog: albums, smart rules, ratings, flags, search |
| `lightcraft-preview` | L3 | `crates/preview/` | Multi-resolution thumbnail and full-resolution preview LRU memory cache |
| `lightcraft-gpu` | L3 | `crates/gpu/` | WGSL shader pipeline twin of the CPU develop pipeline (Metal/Vulkan/DirectX) |
| `lightcraft-merge` | L3 | `crates/merge/` | HDR exposure alignment/deghosting and multi-image panorama stitching |
| `lightcraft-segment` | L3 | `crates/segment/` | SAM 3 neural inference in pure Rust, tokenizers, safetensors weight loading |
| `lightcraft-engine` | L4 | `crates/engine/` | Central engine: session state, undo/redo stack, command dispatch, background jobs |
| `lightcraft-mcp` | L5 | `crates/mcp/` | Model Context Protocol JSON-RPC server over stdio for AI agent automation |
| `lightcraft-ui-egui` | L5 | `crates/ui-egui/` | Touch & desktop UI frontend: Liquid Glass theme, panels, gestures, widgets |

---

## 4. Complete Directory & Source File Map

### User Interface Layer (`crates/ui-egui/src/`)
* **`lib.rs`**: Core egui application coordinator (`LightcraftApp`), toast system, modal state.
* **`theme.rs`**: Apple Liquid Glass styling, frosted dark glass colors (`rgba(16, 18, 24, 0.88)`), corner radiuses, and touch mode toggle (`is_touch_ui()`).
* **`touch.rs`**: Touch event synthesizer, pointer radius management, and kinetic touch physics.
* **`panels/`**:
  * **`panels/grid.rs`**: Library thumbnail grid view, multi-selection bar ("Select All", "Deselect", "Export (N)").
  * **`panels/detail.rs`**: Main photo viewport. Touch gesture arbiter (pan, pinch-to-zoom, Before/After comparison, mask pins and drag handles).
  * **`panels/masking.rs`**: Mask list, component operations (+ Add, − Subtract), local adjustment sliders, eye toggle.
  * **`panels/dialogs.rs`**: Modal dialogs with 32pt circular Apple close buttons (Batch Export, Settings, Welcome, Album Management).
  * **`panels/edit.rs`**: Develop adjustments (Tone, Exposure, Contrast, Highlights, Shadows, Whites, Blacks, Curves, HSL).
  * **`panels/left.rs`**: Left collapsible sidebar (Library Albums, Smart Collections, Import folders).
  * **`panels/presets.rs`**: Presets sidebar (Color, Creative, B&W styles) and History state list.
  * **`panels/bottombar.rs`**: Filmstrip thumbnail drawer and view mode switchers (Grid / Detail / Compare).
  * **`panels/topbar.rs`**: Top header with title, cloud status, export action, and mode selector.
* **`tests_panel_audit.rs`**: Headless test suite that renders and captures all 12 panels at native iPad Retina resolution (`2360 × 1640` px) and validates close button hitboxes.

### iOS Native & Metal Bridge (`ios/`)
* **`ios/LightCraft/`**: Swift application layer.
  * `PhotoPickerBridge.swift`: Manages `MTKView`, translates touch coordinates, displays Apple `PHPickerViewController`.
  * `SceneDelegate.swift`: Window setup, safe-area inset propagation, background suspension.
* **`ios/lightcraft-ios/`**: Rust C-FFI static library.
  * `src/lib.rs`: Exports C-ABI entry points called by Swift.
  * `tests/ios_bridge_test.rs`: 25 bridge integration tests validating touch injection and state transitions.

### Engineering & Mathematics Engine (`crates/engine/` & `crates/pipeline/`)
* **`crates/engine/src/cmd/masks.rs`**: Command dispatch for adding, updating, and removing mask components.
* **`crates/engine/src/segment/mod.rs`**: Segmenter coordinator, download status tracking, model requirement checks.
* **`crates/pipeline/src/masks.rs`**: Mathematical pixel-level rasterizers for Sky, Subject, Background, Linear, Radial, Brush, and Ranges.

---

## 5. End-to-End Touch & Rendering Lifecycle on iPadOS

```
 [User Finger / Apple Pencil]
              │
              ▼
   [UIKit: UIView / MTKView]
   `touchesBegan / touchesMoved / touchesEnded` in PhotoPickerBridge.swift
              │
              ▼ (C-FFI Call)
   `lightcraft_ios_send_touch(phase, x, y, radius, pressure)`
              │
              ▼
   [Rust: lightcraft-ios/src/lib.rs]
   Converts screen points to egui `RawInput` pointer events with 2.0x Retina scale
              │
              ▼
   [Rust: lightcraft-ui-egui/src/panels/detail.rs]
   Gesture Arbiter:
     - Is Masking active? -> Divert touch to Mask Handle / Brush Stroke
     - Is Pinching? -> Update zoom & canvas pan offset
     - Is 1-Finger Pan? -> Gated if drawing tool is active
              │
              ▼
   [Rust: lightcraft-pipeline]
   Executes 32-bit float develop pipeline & mathematical mask calculations
              │
              ▼
   [Rust: egui / wgpu / Metal]
   Tessellates UI meshes and issues draw calls to `CAMetalDrawable`
              │
              ▼
   [iPad Screen: Liquid Retina Display] (120Hz ProMotion Present)
```

---

## 6. How to Build, Test, and Deploy Every Target

### Prerequisite Environment Setup
Ensure Rust, Xcode 16+, and the iOS target are installed:
```bash
# Add iOS target
rustup target add aarch64-apple-ios

# Ensure cargo is in PATH
export PATH="$HOME/.cargo/bin:$PATH"
```

### 1. Build and Deploy to Physical iPad (iPad Air 11-inch M4)
```bash
# 1. Compile the Rust static library for physical iOS device (Release)
cd "/Users/kislayranjanneetandon/Documents/Lightworks Ipad/lightcraft"
cargo build --manifest-path ios/lightcraft-ios/Cargo.toml --target aarch64-apple-ios --release

# 2. Build the Xcode project
xcodebuild -project ios/LightCraftiPad.xcodeproj   -scheme LightCraft   -configuration Debug   -destination "id=00008132-000214443620C01C"   -derivedDataPath ios/DerivedDataDevice   CODE_SIGNING_ALLOWED=YES   build

# 3. Install and launch directly on the connected iPad Air (M4)
xcrun devicectl device install app   --device 00008132-000214443620C01C   ios/DerivedDataDevice/Build/Products/Debug-iphoneos/LightCraft.app

xcrun devicectl device process launch   --device 00008132-000214443620C01C   com.kislay.lightcraftpad
```

### 2. Run Automated Visual Audit & Capture All 12 Panel Screenshots
This command tests every panel, validates Apple HIG close buttons, and writes 12 native Retina screenshots (`2360 × 1640` px) to disk:
```bash
cargo test -p lightcraft-ui-egui --lib tests_panel_audit::test_capture_and_validate_all_panels
```

### 3. Run All Masking & iOS Bridge Test Suites
```bash
# iOS Bridge touch and gesture test suite (25 tests)
cargo test --manifest-path ios/lightcraft-ios/Cargo.toml --test ios_bridge_test

# Masking UI test suite (46 tests)
cargo test -p lightcraft-ui-egui --lib tests_masking

# Pipeline mathematical mask rendering tests (17 tests)
cargo test -p lightcraft-pipeline -- masks
```

### 4. Build and Run the macOS Desktop App
```bash
cargo run -p lightcraft --release
```

### 5. Run the CLI Tool & MCP Server
```bash
cargo run -p lightcraft-cli -- --help
```

---

## 7. Installed Skills Reference Guide

The following 5 specialized skills are installed in `.gemini/skills/`, `.agents/skills/`, and archived in `~/Desktop/Lightcraft_iPad_Audit_And_Skills/skills/`:

1. **`designing-for-ipados/`**: Apple HIG rules for iPadOS multi-window, Split View, Stage Manager, floating toolbars, and Apple Pencil touch ergonomics.
2. **`ios-mobile-design/`**: Native typography pairings (SF Pro), Dynamic Type hierarchy, SF Symbols, and modal sheet constraints.
3. **`liquid-glass/`**: Complete guidelines, API reference, and migration workflow for Apple SwiftUI Liquid Glass design language.
4. **`mobile-app-design/`**: 8-point spatial grid, mobile thumb ergonomics, touch target expansion, and accessibility checklists.
5. **`ipad-app-testing/`**: Scripts and patterns for automating iPad simulators and connected physical hardware devices via `xcrun devicectl`.

---

## 8. Visual Screenshot Gallery & Verification Proof

All 13 high-resolution 2360 × 1640 px Retina screenshots are saved in `~/Desktop/Lightcraft_iPad_Audit_And_Skills/screenshots/`:

| Filename | Resolution | Description |
| :--- | :---: | :--- |
| `01_library_grid_multiselect.png` | 2360 × 1640 | Multi-selection mode in Library Grid with "Select All", selection count ("3 selected"), and "Export (3)" action. |
| `02_detail_develop_panel.png` | 2360 × 1640 | Develop panel with Tone, Curve, and Presence sliders, featuring the 32pt circular close button. |
| `03_detail_masking_panel.png` | 2360 × 1640 | Masking panel showing active Sky Gradient, permanently visible eye toggle, and local adjustment sliders. |
| `04_detail_remove_tool.png` | 2360 × 1640 | Spot Removal tool with heal/clone brush controls, feather slider, and circular close button. |
| `05_detail_crop_straighten.png` | 2360 × 1640 | Crop & Straighten tool with aspect ratios (1:1, 4:5, 16:9) and rotation wheel. |
| `06_detail_info_metadata.png` | 2360 × 1640 | Info panel displaying real-time RGB histogram, camera parameters, and EXIF metadata. |
| `07_detail_quick_develop.png` | 2360 × 1640 | Quick Develop panel with fast incremental single-tap exposure and temperature steppers. |
| `08_detail_presets_sidebar.png` | 2360 × 1640 | Presets sidebar on frosted liquid glass material showing Color, Creative, and B&W styles. |
| `09_modal_batch_export.png` | 2360 × 1640 | Liquid glass Batch Export modal with format selectors, quality slider, and 32pt circular close button. |
| `10_modal_settings_preferences.png` | 2360 × 1640 | Preferences dialog with performance/GPU options and circular close button. |
| `11_modal_welcome.png` | 2360 × 1640 | Welcome / onboarding dialog with clean typography and circular close button. |
| `12_left_sidebar_library.png` | 2360 × 1640 | Library organization sidebar showing Albums, Folders, and Smart Collections. |
| `13_ipad_live_hardware.png` | 2360 × 1640 | Direct screenshot captured from physical iPad Air 11-inch (M4) running the app. |

---

## 9. Developer Handover Checklist & Next Steps

When continuing development or preparing for TestFlight distribution:
- [x] **Touch Targets:** Verify all interactive buttons are at least 44 × 44 pt.
- [x] **Close Buttons:** Ensure every modal sheet and sidebar provides an explicit circular dismiss control.
- [x] **Liquid Glass Theme:** Keep panel backgrounds translucent (`rgba(16, 18, 24, 0.88)`) to maintain canvas awareness.
- [x] **Masking Architecture:** Retain zero-download built-in mathematical masks for Sky, Subject, and Gradients.
- [ ] **TestFlight Packaging:** Configure distribution provisioning profiles in `ios/LightCraftiPad.xcodeproj`.
- [ ] **Native Apple Vision Integration:** For advanced interactive object clicking without downloads, connect `VNGenerateForegroundInstanceMaskRequest` in `PhotoPickerBridge.swift`.
