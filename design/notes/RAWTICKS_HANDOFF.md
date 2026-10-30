# RawTicks — handoff for a new thread

Goal: a native iPad + iPhone raw photo editor called **RawTicks**: LightCraft's Rust backend (engine, raw decode,
develop pipeline, catalog, masks) with a **new UI written from scratch**, built to the V4 design.
Paste this file into the first message of the new thread.

---

## 1. Decision: fork, and credit

**Recommendation: fork `storytold/lightcraft`, then rename the fork to `rawticks`** (GitHub: Settings → rename).

- Keeps full history and automatic "forked from storytold/lightcraft" credit.
- The backend crates (`engine`, `develop`, `pipeline`, `raw`, `catalog`, `segment`, ...) stay mergeable with upstream
  fixes, so RawTicks keeps getting raw-format, colour and mask improvements for free.
- The old UI crate (`crates/ui-egui`) and desktop apps can be deleted or left unused in the fork. If a clean history is
  preferred, start a new repo instead and add the crates as a git subtree/submodule. Forking is simpler.
- **Licence:** LightCraft is `MIT OR Apache-2.0` (see `LICENSE-MIT`, `LICENSE-APACHE`, `NOTICE` in the repo). Keep those
  files, keep upstream copyright notices, and add to `NOTICE`:
  "RawTicks is based on LightCraft by the ArtCraft Team / storytold (https://github.com/storytold/lightcraft)."
  Do not use the ArtCraft name, wordmark or logos in `docs/brand/` (trademarks, not covered by the licence).
- **Clean-room rule carries over (non-negotiable):** no Adobe assets, icons, presets, profiles, fonts or screenshots in
  the repo. UI font is Inter (OFL). Every asset needs an entry in `assets/ATTRIBUTION.md`.

### Credit checklist — do these in RawTicks' first commit

- [ ] Keep `LICENSE-MIT`, `LICENSE-APACHE` and `NOTICE` untouched (the licences require it). `NOTICE` currently starts:
      "LightCraft — Copyright (c) 2026 ArtCraft Team and the LightCraft contributors. MIT or Apache-2.0."
- [ ] Add below it in `NOTICE`: "RawTicks is based on LightCraft by the ArtCraft Team and contributors
      (https://github.com/storytold/lightcraft). Modifications and the new UI: Copyright (c) 2026 <your name>."
- [ ] README: an "Acknowledgements" section linking upstream with the same sentence.
- [ ] Keep copyright/licence headers in every file reused from upstream.
- [ ] Do not use the ArtCraft name, wordmark or logos (`docs/brand/`); remove that folder from RawTicks or leave it unused.
- [ ] Keep the repo a GitHub fork (rename it; do not detach) so "forked from storytold/lightcraft" stays visible.

## 2. Links

| What | Where |
|---|---|
| Upstream | https://github.com/storytold/lightcraft |
| Existing fork (iPad port, my work) | https://github.com/KislayTandon22/lightcraft |
| iPad port PR | https://github.com/storytold/lightcraft/pull/2950 (branch `ios-port`) |
| Working branch with the V4 UI attempt | fork branch `ui-v4-shell` (local checkout: `/Users/kislayranjanneetandon/Documents/Lightworks Ipad/lightcraft`) |
| **V4 design (source of truth)** | https://claude.ai/artifact/WnTHFZF9smZ7X1aGc6mmxp — 21 boards = 7 screens × (iPhone, iPad landscape, iPad portrait) |
| Local V4 reference PNGs | `/private/tmp/claude-501/-Users-kislayranjanneetandon-Documents-Lightworks-Ipad/397cd37c-bb18-4929-a2aa-d6423a15b17a/scratchpad/spec/v4_*.png` (scratchpad is temporary: copy them into the new repo under `design/v4/` first) |
| Previous session transcript | `/Users/kislayranjanneetandon/.claude/projects/-Users-kislayranjanneetandon-Documents-Lightworks-Ipad/397cd37c-bb18-4929-a2aa-d6423a15b17a.jsonl` |
| Notes in the working folder | `PR_DESCRIPTION.md`, `UI_V4_BUILD_PLAN.md`, `IPAD_DESIGN_SPEC.md`, `UX_PANEL_SPECS.md`, `AUDIT_LOG.md` (all in `/Users/kislayranjanneetandon/Documents/Lightworks Ipad/`) |
| Repo agent instructions | `lightcraft/CLAUDE.md` (never-crash rules, clean-room, quality gates: `cargo xtask ci --quick`) |

## 3. What the backend gives you (reuse, do not rewrite)

Workspace crates (layered; nothing below L5 depends on a UI): `geom, color, raster, tiff` → `raw, codecs, meta, develop`
→ `pipeline` → `catalog` → `engine` → UI. Also `denoise`, `segment`, `inpaint`, `faces`, `scenes`, `gpu`.

- **Everything is a command** in `crates/engine` (id, params, run). UI, CLI, MCP and the control channel all dispatch by
  id. Example: `engine.execute {"command":"develop.set","params":{"control":"light.exposure","value":0.35}}`.
  Every slider is a `develop` control spec (`crates/develop/src/controls.rs`: id, label, section, min/max/default).
  This is the contract the new UI should be built on.
- Headless rendering and scripted UI for tests: `lightcraft-cli snapshot --demo --script x.jsonl -o out.png --size WxH`
  (see `docs/control-protocol.md`). Good for the build→snapshot→compare loop with any UI toolkit if the UI can render
  headless; otherwise use the simulator.
- iOS bridge already exists: `ios/lightcraft-ios` (Rust staticlib, wgpu/Metal) plus a Swift host in `ios/LightCraft/`
  (photo picker, share sheet, Files bookmarks, keyboard, safe-area). Apple Vision subject masking is registered from
  Swift (`VNGenerateForegroundInstanceMaskRequest`); I added a Rust region-grow fallback
  (`crates/engine/src/segment/region.rs`) for taps where Vision finds nothing (sky, foliage, backgrounds).
- Xcode project: `ios/LightCraftiPad.xcodeproj` (bundle `com.kislay.lightcraftpad`); a build phase runs
  `cargo build --target aarch64-apple-ios[-sim] --release` and copies `liblightcraft_ios.a`.
- Models: AI Denoise and SAM 3 need downloaded models; iOS uses Vision instead of SAM 3 so no mask download is needed.

## 4. Recommended UI approach (decide this first in the new thread)

The egui UI never reached V4 quality on touch: egui gives you no native text input, no native menus/sheets/popovers,
no accessibility-grade controls, no real glass/blur, and every touch behaviour was hand-built. Hundreds of hours of that
are in `crates/ui-egui`. Options:

1. **SwiftUI (recommended) over the Rust engine.** Keep the engine as a library; expose it to Swift through a small C ABI
   (or UniFFI): `execute(command, json) -> json`, a render surface/texture handoff (Metal), and event callbacks.
   Real sheets, menus, keyboard, pickers, VoiceOver, Dynamic Type, and `Material` glass come free. V4 maps naturally to
   SwiftUI. The canvas (photo + masks + crop overlay) stays a Metal view fed by the Rust renderer.
2. egui again, but only for the photo canvas, with SwiftUI chrome around it (hybrid). Smaller step, same engine contract.
3. Another Rust UI toolkit (Slint, Makepad). Less proven on iOS; not recommended.

Whichever is chosen: build **one screen at a time to V4, verify against its three boards (iPhone / iPad landscape /
iPad portrait) before starting the next**, and keep the engine command contract as the only coupling.

## 5. V4 design language (from the artifact)

- Floating glass bars: 60pt tall, 8pt from screen edges, corner radius 28–30; 44pt controls; no outlines or dividers.
- Selected state = soft white oval with `#4aa3ff` content; exactly **one** filled `#0a84ff` button per screen.
- Bottom mode capsule: Library / Edit / Crop / Heal / Mask / Looks / History (More on narrow widths).
- Library: top bar `All Photos ▾`, search, Sort, Filter pill, Select, blue Import; rounded tiles; bottom row has a count
  pill ("64 of 240 · Newest first"), the mode capsule, and a grid-size slider pill.
- Photo screens: top bar with back, undo/redo, file name + "Edited", pick/reject, 5 stars, sort/share; filmstrip; mode capsule.
- Edit inspector: title + Reset, histogram with clip triangles, Auto/B&W/HDR pills, Profile row, 44pt capsule sliders with
  blue fill from the neutral point and a round reset button, "Tone curve <preset> ›" row, bottom group tabs
  Light / Colour / Effects / Detail / Optics (only that group's sliders). iPhone: compact sheet (group dropdown, Profile,
  parameter chips, one ruler slider).
- Dialogs/sheets: glass card, 28pt radius, title + 44pt close, one blue footer pill, optional neutral Cancel pill;
  iPhone = bottom sheet.
- Target devices: iPad mini 6 (744×1133), iPad 9th gen (810×1080), iPad A16 (820×1180), Air/Pro, iPhone 12 mini (375×812).

## 6. What was built (so you know what to look at or discard)

On fork branch `ui-v4-shell` (egui, touch-only, desktop untouched): mode capsule, photo top bar, filmstrip, Edit inspector
(group tabs, scrolling body, compact iPhone sheet, tone-curve editor, AI Denoise toggle), glass dialog shell, library
top bar, rounded tiles, library count/grid-size pills, sidebar button on the photo bar, UI kit (`ui_kit_touch.rs`).
Not built: Masking, Crop, Looks, Heal/Red-eye, History/Versions/Keywords/People, Library on iPhone and portrait, empty and
import states, menus, Select-mode toolbar, Export wiring.
**Treat this as a reference for behaviours and command wiring, not as code to port.**

## 7. Lessons learned (avoid repeating)

1. Passing clippy/tests proved nothing about matching the design. Only side-by-side comparison with the V4 board counts.
   Review every screen at all three board sizes before calling it done.
2. The first on-device test came too late. Install on a real iPad after **every** screen, and look at it.
3. Working package-by-package and merging without an integration pass produced a patchwork. Walk the full flow
   (Library → photo → Edit → Masking → Export) after each merge.
4. Multi-model workflow (opencode GPT/DeepSeek/GLM, agy/Gemini): useful for isolated work, unreliable for anything
   large. Two writers in one worktree collided; one model rewrote and reformatted a whole 2,600-line file; network
   errors killed runs. Always give a model one worktree, a narrow file list and a "minimal diff" rule, and review
   its diff before merging.
5. egui text inputs pop the iOS keyboard whenever any numeric value box is tapped (egui treats it as text focus).
   A native UI avoids this.
6. egui's headless snapshot renders thumbnails late/skeleton and shows stale state for one frame after a command.
7. Tool gotchas in this environment: the sandbox blocks multi-agent auto-approve launches, scripts containing
   `--dangerously-skip-permissions`, and killing processes (the user must run those). Fable subagents need credits.
   `codex` CLI is not installed. macOS `sed -i` needs `''`.

## 8. Build / install cheatsheet (existing iOS pipeline)

```bash
# iPad (device UDID 00008132-000214443620C01C, "Kislay Ranjan Nee's iPad", iPad Air 11" M4)
cd ios
xcodebuild -project LightCraftiPad.xcodeproj -scheme LightCraftiPad -configuration Release \
  -destination 'id=00008132-000214443620C01C' -derivedDataPath DerivedDataDevice -allowProvisioningUpdates build
xcrun devicectl device install app --device 00008132-000214443620C01C \
  "DerivedDataDevice/Build/Products/Release-iphoneos/LightCraft iPad (fork).app"
xcrun devicectl device process launch --device 00008132-000214443620C01C com.kislay.lightcraftpad   # iPad must be unlocked
```

Simulator: build the lib with `--target aarch64-apple-ios-sim --release`, `xcodebuild` with a `DerivedDataSim` path.
Rename the bundle id, display name and scheme to RawTicks in the new repo (`project.yml` is the xcodegen source).

## 9. Proposed first steps for the new thread

1. Fork `storytold/lightcraft` → rename to `rawticks`; update `README`, `NOTICE` (credit), bundle id/name; copy V4 PNGs to
   `design/v4/`; keep the engine and `ios/lightcraft-ios`, stop depending on `ui-egui` for iOS.
2. Pick the UI approach (section 4) and write the engine bridge: `execute`, render surface, events. Prove it with one
   slider driving a live photo on the iPad.
3. Build screens in this order, each verified against all three V4 boards and installed on the iPad before the next:
   Library (grid, filters, select) → Photo view + filmstrip → Edit → Export sheet → Crop → Masking → Looks → Heal →
   History/Versions → Settings/Import → menus.
4. Maintain a short parity checklist per screen in the repo (board image next to a device screenshot).
5. CI: engine tests (`cargo xtask ci --quick`) plus a UI screenshot job per screen if the toolkit allows headless render.

## 10. Open items from the old thread (backend, still valid)

- Merge `origin/main` (77c0a6ad at last check) into the iPad port; PR #2950 needs a rebase.
- Restrict multi-select / gesture commands and Glass theme selection to touch.
- Object detection: Vision handles salient subjects; region-grow handles the rest. Both untested on real photos on the
  device; consider an on-device interactive segmenter for general objects.
- Accessibility integration test failure vs main was not investigated.
- Optional cleanup: `target/debug/deps` and `ios/target` (disk).
