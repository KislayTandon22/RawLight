# iPad test checklist

## Safari PWA

- [ ] Build with `CARGO_BUILD_JOBS=2 cargo xtask web`.
- [ ] Open over trusted HTTPS on iPad Safari; confirm the demo library appears.
- [ ] Add to Home Screen and launch standalone.
- [ ] Check portrait/landscape and safe-area spacing; rotate and resize in Stage Manager if available.
- [ ] Pinch to zoom, two-finger pan, tap/drag sliders, and double-tap fit/zoom.
- [ ] Import a photo from Files, reload, and confirm it remains in the library.
- [ ] Export an image and back up the library.
- [ ] In Safari Web Inspector, confirm no HTTP secure-context warning and check `navigator.storage` / WebGL availability.

## Native iOS (pending full Xcode)

- [ ] Build simulator and device targets with Xcode.
- [ ] Launch on iPad simulator; confirm demo photos render and an Exposure slider changes the image.
- [ ] Import from Files and Photos into the app sandbox; export through the share sheet.
- [ ] Verify pinch, pan, double-tap fit/100%, long press, undo/redo affordance and Pencil pressure.
- [ ] Exercise a large RAW preview/export and confirm memory stays bounded.
- [ ] Rotate, use split view and Stage Manager, and verify safe areas and panel layout.
- [ ] Install on the connected iPad with a free Apple ID and validate signing/relaunch behavior.
