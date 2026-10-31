import SwiftUI

/// People: download the face models, find faces, name them, browse who is in the library.
struct PeopleView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    struct FaceModel: Identifiable {
        let id: String, name: String, role: String, bytes: Int, installed: Bool, selected: Bool
        let licence: String, notice: String, provenance: String
    }
    struct Face: Identifiable, Hashable {
        let photo: UInt64, index: Int, view: CGRect, suggestion: String?
        var id: String { "\(photo)-\(index)" }
    }
    struct Person: Identifiable { let name: String, count: Int, photo: UInt64, face: CGRect; var id: String { name } }

    @State private var models: [FaceModel] = []
    @State private var progress: [String: Double] = [:]
    @State private var pendingDownload: FaceModel?
    @State private var people: [Person] = []
    @State private var unnamed: [Face] = []
    @State private var unnamedTotal = 0
    @State private var selection: Set<String> = []
    @State private var naming = false
    @State private var name = ""
    @State private var scanning = false
    @State private var scanned = 0
    @State private var scanFaces = 0
    @State private var scanTask: Task<Void, Never>?
    @State private var shown: String?
    @State private var shownFaces: [Face] = []
    @State private var message: String?

    private var detectorReady: Bool { models.contains { $0.role.lowercased().contains("detect") && $0.installed } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    modelsSection
                    if detectorReady { scanSection }
                    if !people.isEmpty { peopleSection }
                    if !unnamed.isEmpty { unnamedSection }
                    if let message { Text(message).font(.footnote).foregroundStyle(Theme.accentSoft) }
                }
                .padding(16)
            }
            .navigationTitle("People").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { scanTask?.cancel(); dismiss() } } }
            .task { await refresh(); await pollDownloads() }
            .alert("Name \(selection.count) face\(selection.count == 1 ? "" : "s")", isPresented: $naming) {
                TextField("Name", text: $name)
                Button("Save") { let n = name; name = ""; Task { await nameSelected(n) } }
                Button("Cancel", role: .cancel) { name = "" }
            }
            .sheet(item: $pendingDownload) { m in terms(m).presentationDetents([.medium]) }
        }
        .presentationBackground(.ultraThinMaterial).presentationCornerRadius(28)
    }

    // MARK: models

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Face models").font(.headline)
            Text("Faces are found and matched on this device. The models are not bundled; each one is an optional download you accept first.").font(.footnote).foregroundStyle(.secondary)
            ForEach(models) { m in
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.name).font(.subheadline.weight(.semibold))
                        Text("\(m.role.capitalized) · \(ByteCountFormatter.string(fromByteCount: Int64(m.bytes), countStyle: .file)) · \(m.licence)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if m.installed { Label("Installed", systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(Theme.accentSoft) }
                    else if let p = progress[m.id] { ProgressView(value: p).frame(width: 70).tint(Theme.accent) }
                    else { Button("Download") { pendingDownload = m }.buttonStyle(.borderedProminent).tint(Theme.accent) }
                }
                .padding(12).fieldBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func terms(_ m: FaceModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(m.name).font(.title3.weight(.semibold))
            Text(m.notice).font(.subheadline)
            if !m.provenance.isEmpty { Text(m.provenance).font(.footnote).foregroundStyle(.secondary) }
            Spacer()
            Button {
                pendingDownload = nil
                Task { await download(m) }
            } label: { Text("I accept, download").font(.headline).frame(maxWidth: .infinity).frame(height: 50).background(Theme.accent, in: Capsule()).foregroundStyle(.white) }
            Button("Cancel") { pendingDownload = nil }.frame(maxWidth: .infinity)
        }
        .padding(20)
    }

    // MARK: scan

    private var scanSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if scanning { scanTask?.cancel() } else { scanTask = Task { await scan() } }
            } label: {
                HStack {
                    Image(systemName: scanning ? "stop.circle" : "face.dashed")
                    Text(scanning ? "Stop (\(scanned)/\(model.photoIDs.count))" : "Find faces in \(model.photoIDs.count) photos")
                }
                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 48)
                .background(Theme.accent, in: Capsule()).foregroundStyle(.white)
            }
            .accessibilityIdentifier("people.scan")
            if scanFaces > 0 || scanned > 0 { Text("\(scanFaces) faces found in \(scanned) photos").font(.footnote).foregroundStyle(.secondary) }
        }
    }

    // MARK: people and unnamed

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("People").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(people) { p in
                        Button { Task { await show(p.name) } } label: {
                            VStack(spacing: 6) {
                                FaceCrop(photo: p.photo, rect: p.face).frame(width: 76, height: 76).clipShape(Circle())
                                    .overlay(Circle().stroke(shown == p.name ? Theme.accent : .clear, lineWidth: 3))
                                Text(p.name).font(.caption.weight(.medium)).lineLimit(1)
                                Text("\(p.count)").font(.caption2).foregroundStyle(.secondary)
                            }.frame(width: 84)
                        }.buttonStyle(.plain)
                    }
                }
            }
            if let shown, !shownFaces.isEmpty {
                Text("\(shown) · tap a face to open the photo").font(.footnote).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
                    ForEach(shownFaces) { f in
                        Button { model.openPhoto = f.photo; dismiss() } label: { FaceCrop(photo: f.photo, rect: f.view).aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12)) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var unnamedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Who is this? (\(unnamedTotal))").font(.headline)
                Spacer()
                if unnamed.contains(where: { $0.suggestion != nil }) { Button("Accept suggestions") { Task { await acceptSuggestions() } }.font(.subheadline) }
                Button(selection.isEmpty ? "Select all" : "Name \(selection.count)") {
                    if selection.isEmpty { selection = Set(unnamed.map(\.id)) } else { naming = true }
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent).accessibilityIdentifier("people.name")
            }
            if !people.isEmpty && !selection.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(people) { p in Button(p.name) { Task { await nameSelected(p.name) } }.buttonStyle(.bordered).tint(.gray) } }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                ForEach(unnamed) { f in
                    Button { if selection.contains(f.id) { selection.remove(f.id) } else { selection.insert(f.id) } } label: {
                        FaceCrop(photo: f.photo, rect: f.view).aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(alignment: .bottom) { if let s = f.suggestion { Text(s).font(.caption2.weight(.semibold)).padding(.horizontal, 6).background(.ultraThinMaterial, in: Capsule()).padding(4) } }
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selection.contains(f.id) ? Theme.accent : .clear, lineWidth: 3))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: actions

    private func refresh() async {
        let engine = model.engine
        if let d = try? await engine.execute("faces.models.list") as? [String: Any], let arr = d["models"] as? [[String: Any]] {
            models = arr.compactMap { m in
                guard let id = m["id"] as? String else { return nil }
                let lic = m["licence"] as? [String: Any]
                return FaceModel(id: id, name: m["name"] as? String ?? id, role: m["role"] as? String ?? "", bytes: (m["sizeBytes"] as? NSNumber)?.intValue ?? 0,
                                 installed: m["installed"] as? Bool ?? false, selected: m["selected"] as? Bool ?? false,
                                 licence: lic?["name"] as? String ?? "", notice: lic?["notice"] as? String ?? "", provenance: m["provenance"] as? String ?? "")
            }
        }
        if let arr = try? await engine.execute("faces.people") as? [[String: Any]] {
            people = arr.compactMap { p in
                guard let n = p["name"] as? String, let ph = (p["photo"] as? NSNumber)?.uint64Value, let r = Self.rect(p["face"]) else { return nil }
                return Person(name: n, count: (p["count"] as? NSNumber)?.intValue ?? 0, photo: ph, face: r)
            }
        }
        if let d = try? await engine.execute("faces.unnamed", ["limit": 120]) as? [String: Any] {
            unnamedTotal = (d["total"] as? NSNumber)?.intValue ?? 0
            unnamed = ((d["faces"] as? [[String: Any]]) ?? []).compactMap(Self.face)
        }
        let ids = Set(people.map(\.photo) + unnamed.map(\.photo))
        for id in ids { await model.thumbnail(id) }
    }

    private static func rect(_ v: Any?) -> CGRect? {
        guard let d = v as? [String: Any], let x0 = (d["x0"] as? NSNumber)?.doubleValue, let y0 = (d["y0"] as? NSNumber)?.doubleValue,
              let x1 = (d["x1"] as? NSNumber)?.doubleValue, let y1 = (d["y1"] as? NSNumber)?.doubleValue else { return nil }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    private static func face(_ d: [String: Any]) -> Face? {
        guard let ph = (d["photo"] as? NSNumber)?.uint64Value, let i = (d["index"] as? NSNumber)?.intValue, let r = rect(d["view"] ?? d["rect"]) else { return nil }
        return Face(photo: ph, index: i, view: r, suggestion: (d["suggestion"] as? [String: Any])?["name"] as? String)
    }

    private func download(_ m: FaceModel) async {
        do { _ = try await model.engine.execute("faces.models.download", ["id": m.id, "acknowledged": true]); progress[m.id] = 0; message = nil }
        catch { message = error.localizedDescription; return }
        await pollDownloads()
    }

    private func pollDownloads() async {
        while !Task.isCancelled {
            guard let d = try? await model.engine.execute("faces.models.downloads") as? [String: Any] else { return }
            var running = false
            for row in (d["downloads"] as? [[String: Any]]) ?? [] {
                guard let id = row["id"] as? String, let state = row["state"] as? String else { continue }
                if state == "running" {
                    running = true
                    let total = (row["total"] as? NSNumber)?.doubleValue ?? 0, bytes = (row["bytes"] as? NSNumber)?.doubleValue ?? 0
                    progress[id] = total > 0 ? bytes / total : 0.02
                } else {
                    progress[id] = nil
                    if state == "failed" { message = (row["error"] as? String) ?? "Download failed." }
                }
            }
            if !running { break }
            try? await Task.sleep(for: .seconds(1))
        }
        progress = progress.filter { _ in false }
        await refresh()
    }

    private func scan() async {
        scanning = true; scanned = 0; scanFaces = 0
        defer { scanning = false }
        let ids = model.photoIDs
        for start in stride(from: 0, to: ids.count, by: 4) {
            if Task.isCancelled { break }
            let chunk = Array(ids[start..<min(start + 4, ids.count)])
            do {
                if let d = try await model.engine.execute("faces.detect", ["ids": chunk]) as? [String: Any] {
                    for ph in (d["photos"] as? [[String: Any]]) ?? [] { scanFaces += ((ph["faces"] as? [Any])?.count ?? 0) }
                }
            } catch { message = error.localizedDescription; break }
            scanned = min(start + 4, ids.count)
        }
        await refresh()
    }

    private func nameSelected(_ n: String) async {
        let trimmed = n.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let faces = unnamed.filter { selection.contains($0.id) }.map { ["photo": $0.photo, "index": $0.index] as [String: Any] }
        guard !faces.isEmpty else { return }
        do { _ = try await model.engine.execute("faces.nameFaces", ["faces": faces, "name": trimmed]); message = nil } catch { message = error.localizedDescription }
        selection = []
        await refresh()
    }

    private func acceptSuggestions() async {
        for (name, group) in Dictionary(grouping: unnamed.filter { $0.suggestion != nil }, by: { $0.suggestion ?? "" }) {
            let faces = group.map { ["photo": $0.photo, "index": $0.index] as [String: Any] }
            _ = try? await model.engine.execute("faces.nameFaces", ["faces": faces, "name": name])
        }
        await refresh()
    }

    private func show(_ name: String) async {
        if shown == name { shown = nil; shownFaces = []; return }
        shown = name
        if let d = try? await model.engine.execute("faces.person", ["name": name, "more": 0]) as? [String: Any] {
            shownFaces = ((d["confirmed"] as? [[String: Any]]) ?? []).compactMap(Self.face)
            for f in shownFaces { await model.thumbnail(f.photo) }
        }
    }
}

/// The part of a photo's thumbnail inside a normalized rectangle (a face).
struct FaceCrop: View {
    @Environment(AppModel.self) private var model
    let photo: UInt64
    let rect: CGRect
    var body: some View {
        Color(white: 0.14).overlay {
            if let img = model.thumbs[photo]?.cropped(to: rect) { Image(uiImage: img).resizable().scaledToFill() }
        }
        .clipped()
    }
}

extension UIImage {
    /// The area inside a rectangle given as fractions of the image (nil when it is empty).
    func cropped(to r: CGRect) -> UIImage? {
        guard let cg = cgImage else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let box = CGRect(x: max(0, r.minX) * w, y: max(0, r.minY) * h, width: min(1, r.width) * w, height: min(1, r.height) * h).integral.intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard box.width >= 2, box.height >= 2, let part = cg.cropping(to: box) else { return nil }
        return UIImage(cgImage: part)
    }
}
