#!/bin/sh
# Build the Rust library for Android and assemble a debug APK.
# usage: android/build.sh [abis, default "arm64-v8a x86_64"]
set -e
cd "$(dirname "$0")"
export PATH=$HOME/.cargo/bin:$PATH
export ANDROID_HOME=${ANDROID_HOME:-$HOME/Android/Sdk}
export ANDROID_NDK_HOME=${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk/27.2.12479018}
export JAVA_HOME=${JAVA_HOME:-$HOME/tools/jdk-17.0.21+9}
ABIS=${*:-"arm64-v8a x86_64"}
T=""; for a in $ABIS; do T="$T -t $a"; done
cargo ndk $T -o app/src/main/jniLibs build ${PROFILE:+--$PROFILE}
${GRADLE:-$HOME/tools/gradle-8.10.2/bin/gradle} --no-daemon :app:assembleDebug -PskipRust
echo "APK: $(pwd)/app/build/outputs/apk/debug/app-debug.apk"
