# LightCraft iPad/iPhone: V4 UI build plan

Reference renders of every V4 board (21): `/private/tmp/claude-501/-Users-kislayranjanneetandon-Documents-Lightworks-Ipad/397cd37c-bb18-4929-a2aa-d6423a15b17a/scratchpad/spec/v4_<screen>_<device>.png` (screens: library, edit, masking, crop, presets, export, export_multi; devices: iphone 390x844, ipad_landscape 1180x820, ipad_portrait 820x1180). Exact CSS values are in the `.dc.html` boards of the design artifact.

## Where we are
Built and on the iPad: the bottom mode capsule only (plus 60pt top/bottom bars, soft selection ovals). Everything else on the device is still the desktop layout in touch sizes. Merged (not yet shown on any screen): UI kit (`ui_kit_touch.rs`) and the Export sheet layout (`panels/export_touch.rs`).

## Rules for every package
- Touch only: gate with `touch_ui && glass::active` (phone: `theme::phone`). The only edit allowed in a shared desktop function is one early `if touch { return <name>_touch::show(..) }` line. Desktop pixels must not change.
- Build the screen from the UI kit components; if a component is missing, add it to `ui_kit_touch.rs` (one owner at a time).
- Match the V4 PNG for that screen on iPad mini 6 (744x1133, 1133x744), iPad 9th gen (810x1080), iPad A16/Air (820x1180, 1180x820) and iPhone 12 mini (375x812). Acceptance = a simulator screenshot next to the V4 PNG.
- No outlines, no dividers, 44pt controls, text >= 12pt, one filled blue button per screen, accessibility names on every control.
- Gates before handing back: `cargo fmt`, `cargo clippy -D warnings`, `cargo test -p lightcraft-ui-egui --lib`, desktop snapshot unchanged.

## Packages (what, files, V4 board)
| # | Package | Main files | V4 board |
|---|---|---|---|
| 0 | Land `main` merge (in progress) | many | none |
| 1 | Shared dialog/sheet shell: rounded glass card, header, scrolling body, ONE blue footer button; every dialog inherits it | dialogs/frame.rs, dialogs.rs | export (shell look) |
| 2 | Photo screens top bar: back / undo / redo, file name + "Edited", Pick / Reject / stars always visible, filter, share; remove the old rating bar and desktop top bar on Detail | topbar_touch.rs, bottombar_touch.rs | edit, masking, crop, presets |
| 3 | Edit inspector: histogram (collapsible), Auto / B&W / HDR pills, Profile dropdown card, slider capsules with reset, bottom group tabs (Light, Colour, Effects, Detail, Optics), tone-curve row; portrait = docked sheet; phone = one ruler slider at a time | edit.rs, right.rs, histogram.rs, profiles.rs, quick_develop.rs | edit |
| 4 | Filmstrip: compact thumbnail row, selected ring, hidden behind a button on phone | strip/grid_touch | edit |
| 5 | Masking panel: add Subject / Sky / Brush / Linear / Radial, mask list with eye toggles, Add / Subtract / Invert, overlay segmented control, per-mask sliders | masking.rs, mask_effects.rs | masking |
| 6 | Crop and geometry: aspect chips, straighten ruler, rotate/flip, guides, Upright, Cancel / Done | crop_overlay.rs, right.rs crop section | crop |
| 7 | Looks / presets: category dropdown, search, thumbnail grid, strength slider, Replace / Add | presets.rs, profiles.rs | presets |
| 8 | Export dialog: wire `export_touch.rs`, multi-photo thumbnail row with "+N", progress | dialogs/export.rs | export, export_multi |
| 9 | Library: grid by day, search with suggestion card, filter menu, sort, size slider, Select mode, Import button, cell states (stars, flag, edited, offline, cannot decode, loading) | grid.rs, grid_touch.rs, filterbar.rs, left.rs, chips.rs | library |
| 10 | AI features and model setup: AI Denoise, Subject / Sky mask, SAM: one shared "model card" with 4 states (not installed: name, size, ONE Download button; downloading: progress + cancel; ready; failed: reason + Retry) | model_setup.rs, panels/denoise.rs, dialogs/sam_model.rs | NEW (no board) |
| 11 | Heal / Remove and Red Eye panels | right.rs sections | NEW (reuse kit) |
| 12 | History, Versions, Keywords, Info, People, Faces panels | activity.rs, keywording.rs, keyword_list.rs, people.rs, person.rs, faces.rs | NEW |
| 13 | Dialogs on the shared shell: Settings (tabs), Import, Cull, Merge, Rename, Slideshow, Print, Keymap (hide on iPad), Credits, Confirm, Updates | dialogs/* | NEW |
| 14 | Menus: the "Menu" button and context menus become glass menu cards (48pt rows, no dividers) | menus.rs, menubar.rs | NEW |
| 15 | Responsive pass: mini / 9th gen / A16 / Air / iPhone 12 mini, landscape + portrait + Split View | all | all |

"NEW" = no V4 board yet. Either I design a board first (comment-driven, like V4) or the model builds it from the kit and the rules and you review the screenshot. Default: build from the kit, review, fix.

## Order
1. Finish and review the `main` merge (package 0), push, update PR #2950.
2. Foundations in parallel (different files, separate worktrees): package 1 (dialog shell) and package 2 (top bar).
3. Edit screen: packages 3 + 4. First screen that should look like V4.
4. Packages 5, 6, 7, 8 in parallel (one file area each).
5. Package 9 (Library), then 10-14, then 15.
6. After each package: simulator screenshots (mini + A16 + iPhone width) vs V4 PNG, then the iPad.

## Method
Models (gpt-6-luna, DeepSeek v4.1 flash, Gemini via agy) write one package each in its own git worktree from a written brief. The lead reviews every diff, runs the gates, merges packages one at a time, rebuilds and checks screenshots. Nothing is pushed without a clean gate run.
