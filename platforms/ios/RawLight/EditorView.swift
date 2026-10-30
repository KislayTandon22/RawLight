import SwiftUI

private let groups: [(name: String, sections: [String])] = [
    ("Light", ["light"]), ("Colour", ["color"]), ("Effects", ["effects", "vignette", "grain"]),
    ("Detail", ["detail"]), ("Optics", ["optics"]),
]

struct EditorView: View {
    @Environment(AppModel.self) private var model
    let photoID: UInt64
    @State private var image: UIImage?
    @State private var controls: [Control] = []
    @State private var group = "Light"
    @State private var renderTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            let layout = wide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            layout {
                ZStack {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().padding(8)
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                inspector.frame(width: wide ? 340 : nil, height: wide ? nil : 330)
            }
            .overlay(alignment: .topLeading) {
                Button { model.openPhoto = nil } label: {
                    Image(systemName: "chevron.left").font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle())
                }
                .padding(12)
            }
        }
        .task {
            try? await model.engine.execute("library.select", ["ids": [photoID], "active": photoID])
            controls = await model.engine.controls()
            await render()
        }
    }

    private var visible: [Control] {
        let secs = groups.first { $0.name == group }?.sections ?? []
        return controls.filter { secs.contains($0.section) }
    }

    private var inspector: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Edit").font(.title3.weight(.semibold))
                Spacer()
                Button("Reset") { Task { try? await model.engine.execute("develop.reset"); controls = await model.engine.controls(); await render() } }
                    .buttonStyle(.bordered).tint(Color(red: 0.29, green: 0.64, blue: 1))
            }
            .padding(.horizontal, 20).padding(.top, 12)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(visible) { c in
                        SliderRow(control: c) { v in set(c.id, v) } reset: { set(c.id, c.def) }
                    }
                }.padding(.horizontal, 16)
            }
            Picker("Group", selection: $group) {
                ForEach(groups, id: \.name) { Text($0.name).tag($0.name) }
            }
            .pickerStyle(.segmented).padding(.horizontal, 16).padding(.bottom, 12)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(8)
    }

    private func set(_ id: String, _ value: Double) {
        if let i = controls.firstIndex(where: { $0.id == id }) { controls[i].value = value }
        renderTask?.cancel()
        renderTask = Task {
            _ = try? await model.engine.execute("develop.set", ["control": id, "value": value])
            if !Task.isCancelled { await render() }
        }
    }

    private func render() async {
        if let img = await model.engine.render(photoID, maxEdge: 1400) { image = img }
    }
}

struct SliderRow: View {
    let control: Control
    let onChange: (Double) -> Void
    let reset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(control.label).font(.subheadline)
                Spacer()
                Text(String(format: "%.\(control.decimals)f", control.value))
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                Button(action: reset) { Image(systemName: "arrow.counterclockwise").font(.caption) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .opacity(control.value == control.def ? 0.3 : 1)
            }
            Slider(value: Binding(get: { control.value }, set: onChange), in: control.min...control.max)
                .tint(Color(red: 0.04, green: 0.52, blue: 1))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
