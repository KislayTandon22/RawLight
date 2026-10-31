# RawLight

A native raw photo editor for iPhone, iPad, Mac, Windows, Linux and Android, built on a pure-Rust
engine (raw decode, develop pipeline, catalog, masks) with a SwiftUI interface on Apple platforms.

> Status: early. iOS/iPadOS is the first target; other platforms follow.

## Platforms

| Platform | Status | Folder |
|---|---|---|
| iOS / iPadOS | builds for simulator | `platforms/ios` |
| macOS | planned | `platforms/macos` |
| Windows (x86_64, arm64) | planned | `platforms/windows` |
| Linux (x86_64, arm64) | planned | `platforms/linux` |
| Android (phone, tablet) | planned | `platforms/android` |

## Build (iOS simulator)

```bash
cd platforms/ios
xcodegen generate
xcodebuild -project RawLight.xcodeproj -scheme RawLight \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedDataSim build
```

Requires Xcode, `xcodegen`, and the Rust targets `aarch64-apple-ios` and `aarch64-apple-ios-sim`.

## Design

The V4 design boards live in `design/v4/`. The UI talks to the engine only through engine commands
(`engine.execute`), see `docs/control-protocol.md`.

## Credits

RawLight is built on **[LightCraft](https://github.com/storytold/lightcraft)** by the ArtCraft Team /
[storytold](https://github.com/storytold) and its contributors: the engine, raw decoding, develop
pipeline, catalog and masking crates are theirs. Thank you. The original README is kept in
[`docs/upstream-README.md`](docs/upstream-README.md).

Also thanks to the open-source projects LightCraft builds on (see `NOTICE`), including wgpu, egui,
and the Inter typeface (SIL OFL). GeoNames data is used under CC BY 4.0.

The iOS app does **not** bundle the **RawNIND** denoise weights (GPL-3.0, from the RawNIND authors, packaged by
[darktable-ai](https://github.com/darktable-org/darktable-ai)). When the user asks, the app downloads them from GitHub over HTTPS
after showing the licence, so the app itself stays free of GPL material. Object and Lasso masks use **MobileSAM** (Apache-2.0,
Core ML conversion by mlboydaisuke, prompt encoding after SamKit), fetched by `platforms/ios/scripts/fetch-models.sh` and never committed.
App Store material is in [`docs/appstore/`](docs/appstore/).

The ArtCraft name, wordmark and logos are trademarks of their owners and are not used here.
RawLight contains no Adobe assets. See `assets/ATTRIBUTION.md`.

## License

MIT OR Apache-2.0, see `LICENSE-MIT`, `LICENSE-APACHE` and `NOTICE`.
