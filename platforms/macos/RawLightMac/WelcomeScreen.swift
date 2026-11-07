import SwiftUI

/// The first screen: pick a library (open, new, recent) or try the demo.
struct WelcomeScreen: View {
    @Environment(LibraryModel.self) private var model
    var body: some View {
        HStack(spacing: 0) {
            hero.frame(maxWidth: .infinity)
            actions.frame(width: 440)
        }
        .background(MacTheme.bg)
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(red: 0.16, green: 0.05, blue: 0.08), Color(red: 0.05, green: 0.04, blue: 0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
            HeroMosaic().opacity(0.9).mask(LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing))
            LinearGradient(colors: [.clear, Color.black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 9).fill(MacTheme.accent).frame(width: 36, height: 36)
                        .overlay(Image(systemName: "sun.max.fill").font(.system(size: 18)).foregroundStyle(.white))
                    Text("RawLight").font(.system(size: 28, weight: .semibold))
                }
                Text("Develop raw photos on your Mac.\nYour files stay where you keep them.")
                    .font(.system(size: 16)).foregroundStyle(.white.opacity(0.7)).lineSpacing(3)
            }.padding(48)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 72)
            Text("Get started").font(.system(size: 20, weight: .semibold))
            Text("Choose where your photos and edits live.").font(.system(size: 13)).foregroundStyle(MacTheme.dim).padding(.top, 4)
            VStack(spacing: 8) {
                action("folder", "Open Library…", "Pick an existing RawLight library folder", primary: true) { model.chooseLibrary(); enterIfOpened() }
                action("plus.rectangle.on.folder", "New Library…", "Make an empty library in a folder you choose") { model.chooseLibrary(); enterIfOpened() }
                action("photo.stack", "Try the demo library", "24 sample photos, nothing is saved") { model.module = "Library" }
            }.padding(.top, 22)
            Text("RECENT").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(MacTheme.dim).padding(.top, 28).padding(.bottom, 6)
            if model.recents.isEmpty {
                Text("Libraries you open will appear here.").font(.system(size: 12)).foregroundStyle(MacTheme.dim)
            } else {
                ForEach(model.recents, id: \.self) { path in
                    let url = URL(fileURLWithPath: path)
                    Button { Task { await model.openLibrary(url); model.module = "Library" } } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "externaldrive").foregroundStyle(MacTheme.dim).frame(width: 18)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(url.lastPathComponent).font(.system(size: 13, weight: .medium))
                                Text(url.deletingLastPathComponent().path).font(.system(size: 11)).foregroundStyle(MacTheme.dim).lineLimit(1).truncationMode(.head)
                            }
                            Spacer()
                        }.padding(.vertical, 5).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            if let e = model.libraryError { Text(e).font(.system(size: 12)).foregroundStyle(MacTheme.accent).padding(.top, 10) }
            Spacer()
            Text("Version 1.0 beta · Rust engine").font(.system(size: 11)).foregroundStyle(MacTheme.dim).padding(.bottom, 20)
        }
        .padding(.horizontal, 40)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(MacTheme.side)
        .overlay(alignment: .leading) { Rectangle().fill(MacTheme.line).frame(width: 1) }
    }

    private func enterIfOpened() { if model.libraryError == nil, model.libraryName != "Demo library" { model.module = "Library" } }

    private func action(_ icon: String, _ title: String, _ sub: String, primary: Bool = false, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 16)).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(sub).font(.system(size: 11)).opacity(0.75)
                }
                Spacer()
            }
            .padding(.horizontal, 14).frame(height: 54)
            .background(primary ? MacTheme.accent : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(.white)
        }.buttonStyle(.plain)
    }
}

/// A soft collage of the demo photos behind the wordmark.
private struct HeroMosaic: View {
    @Environment(LibraryModel.self) private var model
    var body: some View {
        GeometryReader { g in
            let cols = 3, gap: CGFloat = 10
            let w = (g.size.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
            HStack(alignment: .top, spacing: gap) {
                ForEach(0..<cols, id: \.self) { c in
                    VStack(spacing: gap) {
                        ForEach(0..<5, id: \.self) { r in
                            let i = (c * 5 + r * 2 + c) % max(model.ids.count, 1)
                            if i < model.ids.count { MosaicTile(id: model.ids[i]).frame(width: w, height: w * (r % 2 == 0 ? 1.25 : 0.85)) }
                        }
                    }.offset(y: c == 1 ? -60 : c == 2 ? 30 : 0)
                }
            }
        }.clipped()
    }
}

private struct MosaicTile: View {
    @Environment(LibraryModel.self) private var model
    let id: UInt64
    @State private var image: NSImage?
    var body: some View {
        Color(white: 0.14).overlay { if let image { Image(nsImage: image).resizable().scaledToFill() } }
            .clipShape(RoundedRectangle(cornerRadius: 10)).task { image = await model.engine.thumbnail(id, edge: 420) }
    }
}
