plugins { id("com.android.application") }
android {
    namespace = "app.rawlight"   // placeholder: confirm the final package id with the owner before publishing
    compileSdk = 35
    defaultConfig {
        applicationId = "app.rawlight.dev"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
    }
    buildTypes { release { isMinifyEnabled = false } }
    sourceSets["main"].jniLibs.srcDir("src/main/jniLibs")
}

// Build the Rust library with cargo-ndk before packaging, so "Run" in Android Studio is enough.
// ABIs: -PrustAbis="arm64-v8a x86_64" (default both: phone + emulator). Skip with -PskipRust.
val rustAbis = (project.findProperty("rustAbis") as String? ?: "arm64-v8a x86_64").split(" ").filter { it.isNotBlank() }
val cargoBin = File(System.getProperty("user.home"), ".cargo/bin")
val buildRust by tasks.registering(Exec::class) {
    onlyIf { !project.hasProperty("skipRust") && File(cargoBin, "cargo").exists() }
    workingDir = rootDir
    val ndk = File(System.getProperty("user.home"), "Android/Sdk/ndk/27.2.12479018")
    environment("PATH", "${cargoBin}:${System.getenv("PATH")}")
    environment("ANDROID_NDK_HOME", System.getenv("ANDROID_NDK_HOME") ?: ndk.path)
    commandLine(listOf(File(cargoBin, "cargo").path, "ndk") + rustAbis.flatMap { listOf("-t", it) } +
        listOf("-o", "app/src/main/jniLibs", "build"))
}
tasks.matching { it.name == "preBuild" }.configureEach { dependsOn(buildRust) }
