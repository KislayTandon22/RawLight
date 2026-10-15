# Run on iPad

## Current supported path: Safari Home Screen app

Follow [WEB-IPAD.md](WEB-IPAD.md) to build `target/web-site/`, expose it through trusted HTTPS, and use **Share → Add to Home Screen** in iPad Safari. Keep the Mac server/tunnel alive while using that development URL. For normal use, publish `target/web-site/` to an HTTPS host you control.

## Native build status

The native iOS app is not yet packaged. This Mac has the Rust targets `aarch64-apple-ios` and `aarch64-apple-ios-sim`, but `xcodebuild -version` fails because the active developer directory is `/Library/Developer/CommandLineTools`; `/Applications` contains no Xcode app. The simulator, signing setup and native app cannot be built or installed from this environment yet. See [PROGRESS.md](PROGRESS.md) for the blocker and next work.

After installing full Xcode, the intended free-signing flow is:

1. Open the iOS project in Xcode and select the **LightCraftiPad** scheme (the app's display name is **LightCraft iPad (fork)**).
2. In **Signing & Capabilities**, select the personal development team for your Apple ID and set the bundle ID to `com.<your-unique-name>.lightcraftpad` (reverse-DNS lowercase identifier; replace the placeholder with your own unique string).
3. Connect and unlock the iPad, trust the Mac if prompted, and select the iPad as the run destination.
4. Click **Run**. If iPadOS says the developer is not trusted, go to **Settings → General → VPN & Device Management**, select the Personal Team profile, and trust it.
5. A free provisioning profile expires periodically; reconnect the iPad to Xcode and run the app again to refresh it.

The native steps above are the standard Xcode flow and are not verified for this project yet. Use the Safari PWA path until the native project and simulator checks are complete.
