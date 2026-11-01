# RawLight for Android

egui host for the LightCraft engine (stage 1: hello window; engine wiring is next).

## Open in Android Studio
1. `File > Open` and pick this `android/` folder. Let Gradle sync.
2. Gradle must run on **JDK 17**. This machine has it set in `~/.gradle/gradle.properties`
   (`org.gradle.java.home=~/tools/jdk-17.0.21+9`). If sync complains about the JDK, set
   `Settings > Build Tools > Gradle > Gradle JDK` to that folder.
3. Pick a device (the emulator or a phone with USB debugging) and press Run.
   The `buildRust` task runs `cargo ndk` first (needs `~/.cargo/bin/cargo`, `cargo-ndk`, NDK 27.2.12479018).

Default ABIs are `arm64-v8a` (phones) and `x86_64` (emulator). Narrow with `-PrustAbis="arm64-v8a"`; skip Rust with `-PskipRust`.

## Command line
`./build.sh [abis]` builds the Rust library and the debug APK at `app/build/outputs/apk/debug/app-debug.apk`.

## Notes
- On an emulator the app picks wgpu's GLES backend (the emulator's software Vulkan crashes). Phones use Vulkan.
- Use an emulator with hardware graphics (Studio's default `Automatic`/`Hardware`); software GPU froze this machine once.
- `applicationId = app.rawlight.dev` is a placeholder until the owner confirms the package id.
