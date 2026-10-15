# iPad test checklist

## Safari PWA (Automated & Manual)

- [x] Build with `CARGO_BUILD_JOBS=2 cargo xtask web --dev`.
- [x] WebGL2 context initialized and active on iPad viewport (`WebKit WebGL`, 2560x1600 canvas).
- [x] Service Worker registered and shell assets cached (`lightcraft-ipad-shell-v1`).
- [x] Origin Private File System (`navigator.storage.getDirectory()`) verified operational for catalog/image storage.
- [x] Multi-touch pinch-to-zoom and two-finger pan event simulation passed without errors.
- [x] Live UI canvas snapshots captured and verified (`docs/ios/shots/ipad_pwa_running.png`).
- [ ] Open over trusted HTTPS on physical iPad Safari (via `WEB-IPAD.md` instructions).
- [ ] Add to Home Screen and launch standalone full-screen.
- [ ] Check portrait/landscape and safe-area spacing; rotate and resize in Stage Manager.
- [ ] Test pinch to zoom, two-finger pan, tap/drag sliders, and double-tap fit/zoom on touch screen.
- [ ] Import a photo from Files app, reload, and confirm it remains in the library.
- [ ] Export an image and back up the library.

## Native iOS (pending full Xcode)

- [x] Rust iOS static libraries compiled for simulator (`aarch64-apple-ios-sim`) and device (`aarch64-apple-ios`).
- [x] Xcode project generated with bundle ID `com.<me>.lightcraftpad` and fork branding `LightCraft iPad (fork)`.
- [ ] Install Xcode.app and open `ios/LightCraftiPad.xcodeproj`.
- [ ] Launch on iPad simulator; confirm demo photos render and an Exposure slider changes the image.
- [ ] Import from Files and Photos into the app sandbox; export through the share sheet.
- [ ] Verify pinch, pan, double-tap fit/100%, long press, undo/redo affordance and Pencil pressure.
- [ ] Exercise a large RAW preview/export and confirm memory stays bounded.
- [ ] Rotate, use split view and Stage Manager, and verify safe areas and panel layout.
- [ ] Install on the connected iPad with a free Apple ID and validate signing/relaunch behavior.
