# RawLight v1.0.0 (iPad and iPhone beta)

The first shareable build of RawLight: a raw photo editor for iPad and iPhone, built on the LightCraft engine with a SwiftUI interface. Everything runs on the device; nothing is uploaded.

## What's in it
- **Library:** import from Files, folders or Photos; ratings, flags, albums, filters, search; loading screens for big libraries.
- **Develop:** light, colour, curves, detail, effects, optics; crop with straighten and a level line tool; copy and paste settings; history; before and after.
- **Masks:** Subject, Sky, Background, Object (tap) and Lasso (draw around, Apple Pencil supported), Linear, Radial, Brush, Luminance, Colour. Colour-blind-safe overlay colours, one per mask.
- **Bring your own model:** add a Core ML model for the Sky and Background masks in Settings.
- **AI denoise:** an optional RawNIND download (GPL-3.0, about 58 MB) after you accept its licence.
- **Gestures and keys:** swipe to move between photos, rate and pick/reject; keyboard shortcuts; Pencil double-tap and squeeze.
- **Settings:** theme and accent colour, mask colours, selection and denoise models, library and metadata options.

## Known limits
- Test builds only: not on the App Store yet. Camera colour calibration and some compressed raw formats are still being verified.
- The first Object or Lasso tap on a photo can take a few seconds while the on-device model warms up.
- Subject, Sky and Background detection from Apple Vision needs a real device; the simulator falls back to simpler methods.
- Android, Windows, Linux and macOS builds are planned, not included.

## Install for testing
See [`platforms/ios/README.md`](../platforms/ios/README.md): build with Xcode and run on a simulator, or on your own device with a free Apple ID (apps expire after 7 days).

## Credits and licences
LightCraft engine (MIT or Apache-2.0), MobileSAM (Apache-2.0), Inter font (OFL). The optional RawNIND model is GPL-3.0 and is not part of the app. Full list in the app under Settings › Acknowledgements and in `assets/ATTRIBUTION.md`.
