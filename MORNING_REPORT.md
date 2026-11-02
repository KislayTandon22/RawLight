# RawLight Mac: morning report

Branch `macos-app` (PR https://github.com/KislayTandon22/RawLight/pull/1). Latest commit at the time of writing: `3d15440d`.

## Run it

- App: `platforms/macos/build/rel/Build/Products/Release/RawLight.app` (Apple silicon, unsigned).
- DMG: `dist/RawLight-1.0.0-mac-arm64.dmg`.
- Headless test of every screen's flows, with no window and no screen:

```bash
RAWLIGHT_SELFTEST=/tmp/report.txt platforms/macos/build/rel/Build/Products/Release/RawLight.app/Contents/MacOS/RawLight; cat /tmp/report.txt
```

## What the self-test covers (133 passed, 0 failed, 1 skipped)

- Navigation: Library, Develop, Export, next and previous photo, select all and none.
- Library: thumbnail cache, rating, pick, reject, remove flag, import into a new library.
- Develop: all 122 sliders at low and high values, Auto, B&W, HDR, all 41 looks at two strengths, every crop shape and straighten angle, every mask kind and mask adjustment, heal and clone, find dust, undo, redo, history restore, photo info, every tab.
- Export: JPEG, PNG, TIFF and WebP; sRGB, Display P3 and Adobe RGB; 1600 px and full size; with and without a watermark; five photos at once; all nine watermark positions; border, box, vertical text and rotation.
- Watermarks: save, load, export to a file, import from a file, delete.
- Skipped: "Find blemishes" needs the face detector model (Settings, Faces).

## What it cannot cover

The test drives the engine and the model, not mouse clicks. Not yet checked by a person: dragging sliders, clicking on the photo to heal, the key shortcuts while a field has focus, the palette and shortcut sheets, the Settings window, and how the layout looks at other window sizes.

## Speed

- Engine renders take 15 to 35 ms on the demo photos; the first render takes about 0.5 s while the GPU starts, and a warm-up now runs at launch.
- Changes: thumbnails are cached, the filmstrip loads lazily, the Navigator uses a small thumbnail, draft renders are 900 px and full renders 1600 px (same as the iPad app).
- Real RAW files were not timed. If it still feels slow, run with `RAWLIGHT_TIMING=1` and send the render lines.

## Open items

- Windows and Linux installers come from the Rust desktop app and the release workflow (a version tag starts it). Not triggered.
- Intel Mac build: the Rust engine is built for Apple silicon only.
- The app is unsigned, so macOS asks to allow it.
