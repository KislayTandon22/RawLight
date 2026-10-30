# RawLight: full feature set

Source of truth for scope. The engine already implements everything below as commands (316 ids,
see `lightcraft-cli commands`). The UI is SwiftUI on Apple platforms; every feature is reached
through `rl_execute(id, json)`. Status: **E** engine ready, **U** UI built, **-** UI not started.

Legend for devices: **iPad** = landscape/portrait boards, **iPhone** = compact sheet variant (V4).

## 1. Library
| Feature | Engine commands | UI status |
|---|---|---|
| Grid, adaptive tiles, count pill, grid-size slider | `library.state`, `library.sort`, `library.groups` | U (basic) |
| Import: Photos picker, Files folder/files, copy/add/move, rename, keywords, preset on import | `library.import`, `library.importPreview` | U (picker + folder), - (options sheet, preview, duplicates) |
| Camera/card import | `library.devices` | - (iPad USB/SD via Files) |
| Auto import watched folder | `library.autoImport*` | - |
| Sources: All, folders, albums, recently deleted, local browse | `library.source`, `library.folders`, `library.browse` | - |
| Filter bar (rating, flag, label, kind, edited, keyword, camera, lens, date, text) + presets | `library.filter`, `filter.*` | - |
| Sort + date groups | `library.sort`, `library.groups` | - |
| Select mode, multi-select, select by flag/rating, select all | `library.select*` | - |
| Rate, flag (pick/reject), colour label, stacks, virtual copies | `photo.rate`, `photo.flag`, `photo.label`, `stack.*`, `photo.virtualCopy` | - |
| Delete, restore, delete permanently | `photo.delete`, `photo.restore`, `library.emptyRecentlyDeleted` | - |
| Find similar, missing files, relink | `library.findSimilar`, `library.missing`, `photo.relink` | - |
| Albums, smart albums, quick collection | `album.*` | - |
| Keywords (hierarchy, sets, suggest) | `keyword.*` | - |
| People (face detect, index, name) | `faces.*` (models download) | - |
| Metadata panel (info, GPS, copyright), presets, place names | `photo.setMeta`, `metadata.*` | - |
| Lightroom catalog import | `library.importLightroom` | - |
| Library maintenance (info, optimise, clear previews, smart previews) | `library.info`, `library.compact`, `library.smartPreviews` | - |

## 2. Photo view / Edit shell
| Feature | Engine | UI |
|---|---|---|
| Photo top bar: back, undo/redo, name + Edited, pick/reject, stars, share | `edit.undo/redo`, `photo.*` | partial (back only) |
| Filmstrip, next/previous | `library.next/previous` | - |
| Zoom/pan canvas (Metal), fit/fill/100% | render windows (`RenderRequest.window`) | - (static image) |
| Before/After (toggle, split, side by side, copy/swap) | `beforeAfter.*` | - |
| Histogram with clip warnings, RGB readout | render histogram | - |
| Mode capsule: Library / Edit / Crop / Heal / Mask / Looks / History | n/a | - |

## 3. Develop (Edit inspector)
All sliders come from `develop.controls` (13 sections, ~180 controls).
| Group | Controls | UI |
|---|---|---|
| Profile + Auto / B&W / HDR | `develop.profile`, `develop.auto`, `develop.treatment`, `develop.hdr`, `profiles.*`, `profile.*` | - (profile row) |
| Light | exposure, contrast, highlights, shadows, whites, blacks … | U (generic sliders) |
| Colour | WB (temp/tint, picker), vibrance, saturation, HSL mixer, B&W mix, colour grading, calibration | U (temp/tint/vibrance only) |
| Tone curve (point + parametric, presets) | `curve.*` | - |
| Effects | texture, clarity, dehaze, vignette, grain | U |
| Detail | sharpening, noise reduction, AI Denoise (`denoise.*`, model download) | U (sliders), - (AI denoise) |
| Optics | lens profile, distortion, CA, defringe | U |
| Geometry | Upright, vertical/horizontal, rotate, aspect | - |
| Point colour | `pointColor.*` | - |
| Reset section / control, copy / paste / sync settings, match exposure | `develop.reset*`, `develop.copy/paste/sync`, `develop.matchExposure` | partial (reset) |
| Slider UX: neutral-point fill, reset dot, 44pt capsule, numeric entry, ruler on iPhone | n/a | - (V4 styling) |

## 4. Crop and geometry
Crop overlay with handles, aspect presets, rotate/flip, straighten (drag/auto), Upright, guides.
Engine: `crop.*`, `geometry.*`, `photo.rotate*`, `photo.flip*`. **UI: -** (was in old egui UI).

## 5. Masking
Add: subject, sky, background, object (tap), brush, linear/radial gradient, luminance/colour range,
depth. Components (add/subtract/intersect), invert, refine edges/detail, per-mask develop adjustments,
rename/duplicate/visibility overlay. Engine: `mask.*`, `segment.*`. On iOS subject/sky/object use Apple
Vision registered from Swift (`VNGenerateForegroundInstanceMaskRequest`) plus the Rust region-grow fallback
(`crates/engine/src/segment/region.rs`). **UI: -**

## 6. Heal and repair
Spot heal/clone with source refresh, find dust / find blemishes, red-eye, pet-eye/catchlight.
Engine: `spot.*`, `redeye.*`. **UI: -**

## 7. Looks (presets)
Presets (apply, create, update, favourite, rename, folders, import/export, LUT profiles), curve presets,
import of XMP/Lightroom/Luminar presets. Engine: `preset.*`, `curve.presets`, `presets`. **UI: -**

## 8. History and versions
History list/restore/clear, named versions (snapshots), undo/redo. Engine: `history.*`, `version.*`,
`edit.*`, `journal`. **UI: -**

## 9. Merge and AI
HDR merge, panorama, HDR panorama (`merge.*`); AI Denoise (`denoise.*`); face detection and recognition
(`faces.*`); scene tagging. Models are downloaded on demand. **UI: -**

## 10. Export and sharing
Export (format, quality, size, colour space, watermark, sharpening, metadata, rename template), presets,
batch export, contact sheet, share sheet, Save to Photos, Files destination, AirDrop.
Engine: `app.export`, `export.*`. **UI: -**

## 11. Settings
Library location and cache budget, XMP sidecars, GPU/memory, theme (rose-red), model downloads,
keyboard and Pencil, accessibility (VoiceOver, Dynamic Type), about and credits.
Engine: `library.preferences`, `library.xmpPreferences`, `app.gpu`, `app.memoryBudget`.

## 12. Platform and quality requirements
- iPad: pointer, keyboard shortcuts, Apple Pencil (brush masks, double-tap), Stage Manager, multitasking.
- iPhone: compact layouts per V4. One-handed sliders (ruler).
- Never crash: every FFI call is panic-guarded; errors surface as toasts.
- Performance: live slider preview < 100 ms on a 1400px proxy; full-res on release; GPU render path.
- Accessibility, localisation-ready strings, dark theme first.
- Clean-room: no Adobe assets; attribution in `assets/ATTRIBUTION.md`.

## 13. Build order (each step verified on the iPad against its V4 board)
1. **Foundation**: persistent library (done), import (done), Metal canvas with zoom/pan, async render with proxy then full-res, error toasts.
2. **Library** to V4: filters, sort, select mode, ratings/flags, albums, source sidebar, empty/import states.
3. **Photo view + Edit** to V4: top bar, filmstrip, histogram, profile row, capsule sliders, tone curve, undo/redo, before/after.
4. **Export** (full sheet) so work can leave the app.
5. **Crop + geometry**.
6. **Masking** (Vision + brush + gradients + range).
7. **Heal/Red-eye**.
8. **Looks/presets**, **History/Versions**.
9. **Keywords, metadata, People, Merge, AI Denoise**.
10. **Settings, accessibility, iPhone layouts**, then repeat for macOS (shared SwiftUI), then Android/Windows/Linux shells over the same engine.
