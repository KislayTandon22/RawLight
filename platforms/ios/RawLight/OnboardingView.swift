import SwiftUI
import Photos

/// First launch: one screen that asks for everything RawLight needs, once.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    let finish: () -> Void
    @State private var working = false
    @State private var note: String?

    private let items: [(String, String, String)] = [
        ("photo.on.rectangle", "Your photos", "Read the photos you pick and save the ones you export."),
        ("sparkles", "On-device AI", "Subject, sky and object masks and Apple noise reduction run on this device. Nothing is uploaded."),
        ("wand.and.sparkles", "AI Denoise (RawNIND)", "A raw denoise model is included. It is licensed GPL-3.0 and runs on this device only; its source is at github.com/darktable-org/darktable-ai."),
    ]

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 20)
            Text("Welcome to RawLight").font(.largeTitle.weight(.bold))
            Text("One tap sets up everything. You can change any of this later in Settings.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(items, id: \.0) { it in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: it.0).font(.title3).foregroundStyle(Theme.accent).frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) { Text(it.1).font(.headline); Text(it.2).font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
            }
            .padding(18).frame(maxWidth: 560, alignment: .leading).fieldBackground(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            if let note { Text(note).font(.footnote).foregroundStyle(Theme.accentSoft) }
            Spacer()
            Button { Task { await accept() } } label: {
                HStack { if working { ProgressView().tint(.white) }; Text("Agree and continue").font(.headline) }
                    .frame(maxWidth: 420).frame(height: 54).background(Theme.accent, in: Capsule()).foregroundStyle(.white)
            }.buttonStyle(.plain).disabled(working).accessibilityIdentifier("onboarding.continue")
            Text("By continuing you accept the licence terms above.").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 20)
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black.ignoresSafeArea())
    }

    private func accept() async {
        working = true
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        if Bundle.main.url(forResource: "rawdenoise-nind", withExtension: "dtmodel") != nil, !(await model.ensureDenoiseModel()) {
            note = "Denoise model couldn't be set up now; you can add it later in Edit › Detail."
        }
        working = false
        finish()
    }
}
