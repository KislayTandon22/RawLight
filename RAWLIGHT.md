# RawLight

Native iPad + iPhone raw photo editor: LightCraft's Rust backend with a new UI built to the V4 design.

- Design source of truth: `design/v4/` (7 screens x iPhone / iPad landscape / iPad portrait).
- Backend contract: engine commands (`engine.execute {"command": ..., "params": ...}`). The UI is coupled to nothing else.
- `crates/ui-egui` is legacy reference only; iOS must not depend on it.
- Clean-room rule: no Adobe assets. Every asset needs an entry in `assets/ATTRIBUTION.md`.
- Remotes: `upstream` = storytold/lightcraft (merge backend fixes), `origin` = KislayTandon22/lightcraft (rename to RawLight on GitHub).

## Decision: UI is SwiftUI
SwiftUI chrome (sheets, menus, pickers, glass) over the Rust engine through a small C ABI:
`execute(command, json) -> json`, a Metal render surface for the photo canvas, and event callbacks.
`crates/ui-egui` is legacy and gets removed from the iOS build once the bridge no longer needs it.
