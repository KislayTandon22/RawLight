# Native iPad app

LightCraft now runs as a native iPad app (Metal, Apple Silicon, iPadOS 16+). **The desktop apps are unchanged**: every
iPad-specific line is in `ios/`, behind `cfg(target_os = "ios")`, behind the touch layout flag
(`theme::touch_ui`, which only the iPad host sets), or behind a host hook that is `None` everywhere else.

## What this adds
- **`ios/`**: Xcode project (from `project.yml`), Swift bridge (Photos / Files pickers, folder bookmarks, Apple Pencil
  recogniser, Apple Vision subject masks) and the `lightcraft-ios` Rust static library.
- **Touch UI** (`crates/ui-egui`, touch layout only): Liquid-Glass look (`glass.rs`), its own top and bottom bars
  (`topbar_touch.rs`, `bottombar_touch.rs` — `topbar.rs` / `bottombar.rs` only hand over to them on the iPad), landscape /
  portrait / Split View layouts, a bottom bar that slides with a visible cue, a draggable floating rater, finger-sized
  controls, Quick Develop, filter chips (rating, flag, label, edited, original missing), a missing-original badge and banner.
- **Gestures**: two-finger tap = undo, three-finger tap = redo, Pencil double-tap = zoom, Pencil digits 1-5 = rating,
  circle = 0, tick = pick, cross = reject.
- **Library on iPad**: no `flock` on iOS (0xDEAD10CC), container-UUID relink of stale paths at launch, restored folder
  bookmarks, no demo photos, a library that fails to open is reported instead of replaced by a demo one.
- **AI masks without a download**: a host segmenter hook in the engine (`segment/platform.rs`); iOS plugs in Apple Vision.
- **External drives:** photos from a USB drive or network share default to "Add in place" (the iPad's storage is small); the folder
  bookmark is kept while the drive is unplugged and restored when the app returns to the foreground.
- **Auto Tone** in Quick Develop reaches every selected photo in one undo step (`develop.auto` accepts `ids`); the iPad's Auto toast names
  the sliders it moved, and sliders fill with the accent from their neutral value.
- **Roomier iPad menus:** 16pt side padding and a minimum width in popup and context menus, 44pt keyword / preset rows.
- `develop.adjust` / `develop.wb` accept `ids` (Quick Develop's multi-photo nudge, one undo step); without `ids` they behave
  as before.
- **Tooling and docs**: `lightcraft-cli snapshot --touch`, `tools/edit_flow/ui_lint.py` (geometric UI lint), a README install
  section ("Building and installing the native iPad app"), `docs/ios-port.md`.

## Desktop is untouched
Main was built separately and 15 desktop renders (grid, left panel, detail, masking, crop, info, compare, survey, the
filter bar, Settings, Export, About, Shortcuts, Rename) were pixel-diffed against this branch: **0 differ**. Desktop
themes, menus, shortcuts, dialogs, sidebar, mixer and export UI are the ones on `main`; the new commands
(`view.multiSelect`, `input.*`) have no menu entry.

## Methodology
Reproduce on device and simulator, then headlessly in five window sizes; review bottom-up (atoms, panels, screens, flows);
a geometric lint of every widget rectangle; Gemini and DeepSeek as assistant reviewers and CodeRabbit on this PR (each
finding checked against the code); a pixel diff against `main`; fmt / clippy `-D warnings` (ui-egui, engine, catalog, cli,
and `ios/lightcraft-ios` for `aarch64-apple-ios`), `cargo xtask layers` / `assets` / `parity`.

## Testing
- Rebased onto current `main` (egui 0.37 fork). `cargo test -p lightcraft-ui-egui -p lightcraft-engine -p lightcraft-catalog`: all pass except
  `accessibility::every_interactive_node_has_a_name_in_every_view_and_tool`, which panics with "No glyph for ▸" because this machine has no
  `craft-fonts`; it fails the same way on an untouched `origin/main` here, so CI (with the fonts) is the check.
- `cargo clippy --all-targets -D warnings` for ui-egui, engine, catalog, cli and `ios/lightcraft-ios` (`aarch64-apple-ios`).
- Reviewed by four read-only review agents (engine, UI gating, iOS host, past review comments); each finding checked against the code, five
  desktop-behaviour leaks found and gated to the iPad.
- Desktop parity: 24 desktop renders (grid, left panel, square grid, compare, survey, ten Detail panels, eight dialogs) are byte-identical
  between `main` and this branch.
- Built and run on the iPad Pro simulator: import from a Files folder (Copy by default), force-quit and reopen, photos load.
  Built and installed earlier on an iPad Air 11" (M4). Not verifiable in the simulator: Vision masks, real Apple Pencil, iCloud Drive.

## Not in this PR
The earlier iPad work also touched shared features; they are left out to keep this change iPad-only and can follow
separately: the web PWA files, the auto-tone / auto-WB changes, the Develop left sidebar, the colour-mixer and grading
changes, an iPad restyle of the dialogs, and the model-mirror / token settings. Known limits: the iPad's dialogs are the
desktop's windows for now; CJK fonts need `CRAFT_FONTS_DIR`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## UI v4 rebuild (iPad + iPhone, touch only)
The touch UI was rebuilt to match the V4 design boards (7 screens x iPhone / iPad landscape / iPad portrait). Everything is
behind `theme::touch_ui` + `glass::active` (or `theme::phone` for the phone layout), so desktop and web are unchanged.
- **Shell:** one bottom mode capsule (Library / Edit / Crop / Heal / Mask / Looks / History, "More" when narrow) replaces the
  desktop tool rail; 60pt floating glass bars, 44pt controls, no outlines or dividers, one filled blue button per screen.
- **Photo screens:** one long photo top bar (back, undo/redo, name, Pick, Reject, stars, filter, share), a compact label-free
  filmstrip (hidden on iPhone), a floating before/after button instead of the legacy bottom bar.
- **Edit inspector:** a docked glass card with group tabs (Light, Colour, Effects, Detail, Optics) and capsule sliders.
- **Dialogs:** one shared glass card (bottom sheet on iPhone) with a single filled primary action.
- **UI kit:** `ui_kit_touch.rs` (capsule buttons, segmented control, search, menu card, value slider, badges) so every panel
  shares the same parts.

### How it was built
1. Design first: V4 boards exported to reference PNGs; a package-by-package build plan.
2. A headless loop per package: write code, `lightcraft-cli snapshot --demo --touch` at iPad mini (744x1133), iPad A16
   (820x1180), iPad landscape (1180x820) and iPhone (390x844), compare against the V4 PNG, fix, repeat at least three times.
3. Coding was delegated to several models (GPT-class and Gemini via opencode and agy, DeepSeek and GLM free models); each
   worked in its own git worktree on one package. The senior engineer reviewed every diff and screenshot and merged one
   package at a time; fmt, clippy `-D warnings` and the ui-egui tests gate each merge.
4. Device check on iPad simulator and a real iPad after each merge.

Smallest targets: iPad mini 6, iPad 9th gen, iPhone 12 mini; if it works there it works on the larger devices.
