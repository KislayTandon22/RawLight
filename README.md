# RawLight

A native raw photo editor for iPhone, iPad, Mac, Windows, Linux and Android, built on a pure-Rust
engine (raw decode, develop pipeline, catalog, masks) with a SwiftUI interface on Apple platforms.

> Status: v1.0.0 beta for iPad and iPhone ([release notes](docs/RELEASE-v1.0.0.md), [build and test guide](platforms/ios/README.md)). macOS is in beta (Apple silicon `.dmg`). Windows and Linux installers come from the release workflow.

## Platforms

| Platform | Status | Folder |
|---|---|---|
| iOS / iPadOS | v1.0.0 beta (simulator and device) | `platforms/ios` |
| macOS (Apple silicon) | beta: SwiftUI, Library, Develop, Export, watermarks, menu bar, command palette | `platforms/macos` |
| Windows (x64, x86, arm64) | `.exe`/`.msi` built by `.github/workflows/release.yml` | `apps/lightcraft` |
| Linux (x86_64, arm64) | AppImage, `.deb`, `.rpm`, Flatpak built by the same workflow | `apps/lightcraft` |
| Android (phone, tablet) | planned | `platforms/android` |

## Build (iOS simulator)

```bash
cd platforms/ios
xcodegen generate
xcodebuild -project RawLight.xcodeproj -scheme RawLight \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedDataSim build
```

Requires Xcode, `xcodegen`, and the Rust targets `aarch64-apple-ios` and `aarch64-apple-ios-sim`.

## Watermarks

Export can stamp a text or picture watermark: nine positions, separate across and down margins (in percent or pixels on iPad),
rotation, opacity, colour, shadow, and an optional border, padding, background box and rounded corners. Watermarks can be saved,
reused, and shared as one `.json` file with the logo inside. See `docs/watermarks.md`.

## Build (macOS)

```bash
cd platforms/macos
xcodegen generate
xcodebuild -project RawLightMac.xcodeproj -scheme RawLightMac -configuration Release \
  -derivedDataPath build/rel ARCHS=arm64 build
```

Requires Xcode, `xcodegen` and the Rust target `aarch64-apple-darwin`. Shortcuts: `⌘1/2/3` Library, Develop, Export; `⇧⌘I` import;
`⇧⌘E` export; `⇧⌘K` command palette; `⌘/` shortcut list; `1`-`5`, `P`, `X`, `U` to rate and flag.

## Windows and Linux

These platforms use the Rust desktop app in `apps/lightcraft`, since SwiftUI is Apple-only. Pushing a version tag runs the
Release workflow, which builds the Windows installers (x64, x86, arm64) and the Linux AppImage, `.deb`, `.rpm` and Flatpak.

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
