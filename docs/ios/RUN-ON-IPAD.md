# Run on iPad

## Path 1: Instant Safari Home Screen PWA (Recommended for immediate testing)

The WebAssembly build with offline caching is ready and actively running:
1. On your iPad, open Safari and navigate to:
   ```
   https://search-ham-consolidation-hierarchy.trycloudflare.com
   ```
2. Tap the **Share** button in Safari and select **Add to Home Screen**.
3. Launch **LightCraft** from the iPad Home Screen:
   - Full offline execution via Cache-First Service Worker (`lightcraft-ipad-local-v2`).
   - 44pt touch controls, pinch-to-zoom, two-finger pan.
   - 1-tap Lightroom-grade Auto Tone, Auto White Balance, and AI Blemish Healing.

---

## Path 2: Native App via Xcode (`LightCraftiPad.xcodeproj`)

The optimized native iOS release binary (`liblightcraft_ios.a`, 159 MB) is compiled for Apple Silicon ARM64 and staged directly at:
```
ios/build/liblightcraft_ios.a
```

### Steps to Deploy Native App to iPad:

1. **Open Project in Xcode**:
   Double-click or run:
   ```bash
   open ios/LightCraftiPad.xcodeproj
   ```
2. **Configure Signing**:
   - In Xcode, select the **LightCraftiPad** project in the left navigator.
   - Go to the **Signing & Capabilities** tab.
   - Check **Automatically manage signing**.
   - Under **Team**, select your free **Personal Team** (associated with your Apple ID).
   - In **Bundle Identifier**, update `com.example.lightcraftpad` to a unique identifier with your name (e.g. `com.kislay.lightcraftpad`).
3. **Select Your Connected iPad**:
   - Connect your iPad to your MacBook Air with a USB-C cable.
   - Unlock the iPad and tap **Trust This Computer** if prompted.
   - In Xcode's top destination bar, select your connected iPad instead of Any iOS Device.
4. **Build and Run**:
   - Press **Cmd + R** or click the **Play / Run** button in Xcode.
   - Xcode will link the pre-staged `ios/build/liblightcraft_ios.a` and install the native app onto your iPad.
5. **Trust the Certificate on iPad** (first run only):
   - On your iPad, open **Settings → General → VPN & Device Management**.
   - Under *Developer App*, tap your Apple ID email and tap **Trust**.
   - Return to your Home Screen and launch **LightCraft iPad (fork)**.
