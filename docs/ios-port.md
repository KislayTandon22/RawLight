# iPad port (`ios-port`)

Last updated: 2026-10-25

LightCraft now runs as a native iPad app. The rule for this branch: **the iPad changes must not change the macOS,
Windows, Linux or web apps.** Everything iPad-specific is either in `ios/`, behind `cfg(target_os = "ios")`, or behind
the touch layout flag (`crate::theme::touch_ui`, which only the iPad host switches on; `glass::active` is touch + dark).

## What was added

**Host (`ios/`)**
- `ios/LightCraftiPad.xcodeproj` (generated from `ios/project.yml`): iPad-only, iOS 16+, a Rust build phase that builds
  `liblightcraft_ios.a` for the simulator or the device and links it with `-force_load`.
- `ios/lightcraft-ios`: the Rust static library (eframe/wgpu on Metal), the C ABI the Swift side calls, the Pencil
  stroke queue, the segmenter callback.
- `ios/LightCraft/*.swift`: app entry, scene delegate, Photos/Files pickers, security-scoped folder bookmarks, the
  Apple Vision subject-mask bridge, the Pencil gesture recogniser.

**Touch UI (`crates/ui-egui`, touch layout only)**
- Liquid-Glass look (`glass.rs`): floating translucent shells, capsule buttons, rims and shadows (no real backdrop
  blur is possible: the photo and the UI share one layer, so the material is approximated).
- Layouts for landscape, portrait, Split View and Slide Over; a bottom bar that slides sideways with a fade + chevron
  cue; a draggable floating rater when the bar has no room; 40pt hit areas, bigger stars, capsule Menu button,
  solid slider thumbs, iOS switches, a round zoom slider, iPad dialogs (three widths, trailing footer buttons).
- Gestures (`touch.rs`, `pencil.rs`): two-finger tap = undo, three-finger tap = redo, Pencil double-tap = zoom,
  Pencil digits 1-5 = rating, circle = 0, tick = pick, cross = reject (one-stroke $1 and multi-stroke $P recognisers).
- Develop sidebar and Quick Develop rail, filter chips (rating, flag, label, edited, original missing), the missing-original badge and banner,
  pick/reject drawn as a tick and a cross, undo/redo buttons.

**Library on the iPad (`crates/engine`, `crates/catalog`)**
- No `flock` on iOS (a suspended app holding a lock is killed with 0xDEAD10CC).
- `container_relink.rs`: the app container UUID changes between installs, so absolute paths are re-based at launch.
- Demo photos are removed at launch; folders the user picked are restored from bookmarks.
- AI masks use a host segmenter hook (`segment/platform.rs`): iOS plugs in Apple Vision so no model download is needed.
  The mirror/token file is written with owner-only permissions.

**Tooling**
- `lightcraft-cli snapshot --touch` renders the iPad layout headlessly.
- `tools/edit_flow/ui_lint.py` (geometric UI lint over every screen), `panel_audit.py`, flow scripts,
  `docs/button-test-checklist.md`.

## How "iPad only" is enforced

| Mechanism | Where |
| --- | --- |
| `ios/` directory and `cfg(target_os = "ios")` | host, lock skip, export-folder fallback |
| `theme::touch_ui(ctx)` | every layout, size, colour, gesture and dialog change in `ui-egui` |
| `glass::active(ctx)` | the glass bars, shells and dock style (touch + dark) |
| Engine hooks default to "off" | the segmenter hook is `None` unless a host installs one |

The Develop sidebar, the Quick Develop rail entry, the flag glyphs, the Library/Develop module switch, the "+ Library"
button, selection badges, dialog chrome and the desktop keyboard shortcuts are all restored or gated so the desktop
renders as before.

## Methodology

1. **Reproduce on a device and the simulator**, then reproduce headlessly: `lightcraft-cli snapshot --touch --demo
   --script X.jsonl --size 1180x820` (landscape), `820x1180` (portrait), `700x820` / `504x820` (Split View),
   `320x820` (Slide Over).
2. **Bottom-up review**: atoms (a component gallery), then every button, panel, dialog, screen and user flow.
3. **Geometric lint** over every registered widget rectangle: hit targets under 32pt, overlapping controls, widgets off
   the screen. It finds what eyeballing screenshots misses.
4. **AI review as assistants, not authorities**: Gemini (screenshots, through `agy` with `--add-dir` and `view_file`)
   judged each control against the iPadOS Human Interface Guidelines; DeepSeek and Gemini reviewed diffs. Every finding was
   checked against the code before acting; several were wrong and were dropped.
5. **Desktop parity check**: the pre-port commit was built separately and about 120 desktop renders (grid, detail,
   every right panel, left panel, presets, compare/survey, every dialog) were pixel-diffed against the port. What remains is
   listed below.
6. **Gates**: `cargo fmt`, `cargo clippy -D warnings` (ui-egui, engine, catalog, cli, and the iOS crate for
   `aarch64-apple-ios`), the ui-egui tests, device and simulator builds, installs with `devicectl`.

## Shared (not iPad-only) changes

These improve the engine or UI for every platform. They are listed so a reviewer can accept or split them out:
- `develop.adjust` accepts `ids` (nudge several photos in one undo step); auto-edit tuning in `crates/pipeline/src/auto.rs`.
- The colour mixer opens on HSL / All with the Red band; a Global colour-grading wheel; curve split handles are one undo step.
- New commands in the registry: `view.multiSelect`, `input.twoFingerTap`, `input.threeFingerTap`,
  `input.pencilDoubleTap`, `panel.quickDevelop`; an `Apple Glass` theme in the theme list; an export scope (selected / all).
- `segment.model.*` commands are hidden from the menu bar (they need a host).
- Small fetch/segment edits (`crates/fetch`, `crates/segment`).

## Verification and known limits

- ui-egui: 882 tests pass (the export-dialog bulk test is flaky under load, as before this branch).
- Not testable in the simulator: Vision masks ("Could not create inference context") and real Pencil input; check on
  a physical iPad.
- CJK fonts are absent unless `CRAFT_FONTS_DIR` is set; the dock tab strip has square corners (third-party `craft_ui`).
