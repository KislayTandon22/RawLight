# RawLight for iPad and iPhone

SwiftUI app over the Rust engine in `crates/`. Requires macOS with Xcode 26 (iOS 17.5 or later as the deployment target), [xcodegen](https://github.com/yonaskolb/XcodeGen) and Rust with the targets `aarch64-apple-ios` and `aarch64-apple-ios-sim`.

## Build and run

```bash
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
brew install xcodegen
cd platforms/ios
sh scripts/fetch-models.sh        # MobileSAM Core ML files (about 23 MB, checked against fixed hashes)
xcodegen generate
open RawLight.xcodeproj           # pick an iPad or iPhone simulator, press Run
```

The first build compiles the Rust engine and takes several minutes.

### On your own device
Select your device and a development team in Xcode (a free Apple ID works; the app expires after 7 days). Turn on Developer Mode on the device under Settings › Privacy & Security.

## Testing notes
- Photos stay on the device. The only network use is the optional AI denoise download from github.com.
- Subject, Sky and Background masks use Apple Vision, which only works fully on a real device.
- Useful checks: import a raw, try each mask type (Object and Lasso especially), straighten with the Level tool, rate and flag with swipes, switch theme in Settings.
- Report problems with the device, iOS version, the photo's camera model and what you did.

## Layout
- `RawLight/` SwiftUI sources; `UITests/` UI tests; `scripts/` model fetching; `project.yml` the xcodegen project.
- `../../crates/bridge` the C bridge to the engine.
