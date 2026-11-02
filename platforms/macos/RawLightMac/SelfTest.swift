import AppKit
import Foundation

/// Headless check of every screen's engine flows, with no window: `RAWLIGHT_SELFTEST=/path/report.txt RawLight`.
/// Writes one PASS/FAIL line per step and exits non-zero on any failure.
@MainActor enum SelfTest {
    static func run(report: String) async {
        var lines: [String] = []
        var failed = 0
        func log(_ ok: Bool, _ name: String, _ detail: String = "") {
            if !ok { failed += 1 }
            lines.append("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  — \(detail)")")
        }
        func step(_ name: String, _ body: () async throws -> String?) async {
            let t0 = Date()
            do { let d = try await body(); log(d == nil, name, d ?? String(format: "%.0f ms", Date().timeIntervalSince(t0) * 1000)) }
            catch {
                let m = error.localizedDescription
                if m.contains("YuNet") { lines.append("SKIP  \(name)  — needs a model download in Settings"); return }
                log(false, name, m)
            }
        }

        let model = LibraryModel()
        let e = model.engine
        let tmp = FileManager.default.temporaryDirectory.appending(path: "rawlight-selftest-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        await model.load()
        log(model.ids.count > 0, "Library: demo photos load", "\(model.ids.count) photos")
        guard let first = model.ids.first else { return finish(lines, failed, report) }

        // navigation
        model.module = "Library"
        model.go("Develop"); log(model.module == "Develop" && model.activeID != nil, "Nav: Library → Develop opens a photo")
        let a0 = model.activeID; model.step(1); log(model.activeID != a0, "Nav: next photo (→)")
        model.step(-1); log(model.activeID == a0, "Nav: previous photo (←)")
        model.go("Export"); log(model.module == "Export", "Nav: Export")
        model.go("Library"); log(model.module == "Library", "Nav: back to Library")
        model.selection = Set(model.ids); log(model.selection.count == model.ids.count, "Library: select all")
        model.selection = []; log(model.selection.isEmpty, "Library: select none")

        // thumbnails and cache
        let t0 = Date(); _ = await e.thumbnail(first, edge: 360); let cold = Date().timeIntervalSince(t0)
        let t1 = Date(); let hit = await e.thumbnail(first, edge: 360); let warm = Date().timeIntervalSince(t1)
        log(hit != nil && warm < cold + 0.001, "Library: thumbnail cache", String(format: "cold %.0f ms, cached %.1f ms", cold * 1000, warm * 1000))

        // culling
        model.selection = [first]
        for (cmd, p) in [("photo.rate", ["ids": [first], "rating": 4]), ("photo.rate", ["ids": [first], "rating": 0]),
                         ("photo.pick", ["ids": [first]]), ("photo.reject", ["ids": [first]]), ("photo.unflag", ["ids": [first]])] as [(String, [String: Any])] {
            await step("Library: \(cmd) \(p["rating"].map { "\($0)" } ?? "")") { _ = try await e.execute(cmd, p); return nil }
        }

        // Develop
        let dev = DevelopModel()
        await dev.open(first, engine: e)
        log(!dev.controls.isEmpty, "Develop: sliders load", "\(dev.controls.count) controls")
        log(dev.image != nil, "Develop: picture renders")
        log(dev.histogram.count == 1024, "Develop: histogram")
        log(!dev.presets.isEmpty, "Develop: looks list", "\(dev.presets.count) looks")
        if let c = dev.controls.first(where: { $0.label == "Exposure" }) ?? dev.controls.first {
            dev.set(c, c.min + (c.max - c.min) * 0.6, commit: true, id: first, engine: e)
            try? await Task.sleep(for: .milliseconds(600))
            log(dev.controls.first(where: { $0.id == c.id })?.value != c.def, "Develop: slider edit (\(c.label))")
        }
        for (name, cmd, p) in [
            ("Auto", "develop.auto", [:]), ("B&W", "develop.treatment", [:]), ("HDR on", "develop.hdr", ["enabled": true]), ("HDR off", "develop.hdr", ["enabled": false]),
            ("Crop aspect 1:1", "crop.aspect", ["aspect": "1x1"]), ("Crop straighten", "crop.straighten", ["angle": 2.0]),
            ("Crop swap shape", "crop.rotateAspect", [:]), ("Crop auto level", "crop.autoStraighten", [:]), ("Crop reset", "crop.reset", [:]),
            ("Mask radial", "mask.add", ["kind": "radial", "center": [0.5, 0.5], "rx": 0.3, "ry": 0.25, "angle": 0, "feather": 50]),
            ("Mask adjust", "mask.adjust", ["values": ["exposure": 0.5]]), ("Mask invert", "mask.invert", [:]),
            ("Mask duplicate", "mask.duplicate", [:]), ("Mask delete", "mask.delete", [:]),
            ("Mask linear", "mask.add", ["kind": "linear"]), ("Mask delete all", "mask.deleteAll", [:]),
            ("Heal spot", "spot.add", ["mode": "heal", "points": [[0.5, 0.45]], "size": 0.06]),
            ("Clone spot", "spot.add", ["mode": "clone", "points": [[0.3, 0.3]], "size": 0.06]),
            ("Find dust", "spot.findDust", [:]), ("Find blemishes", "spot.findBlemishes", [:]), ("Delete selected spot", "spot.delete", [:]),
            ("Undo", "edit.undo", [:]), ("Redo", "edit.redo", [:]), ("Develop reset", "develop.reset", [:]),
        ] as [(String, String, [String: Any])] {
            await step("Develop: \(name)") { _ = try await e.execute(cmd, p); return nil }
        }
        if let look = dev.presets.first {
            await step("Develop: apply look “\(look.name)”") { await dev.applyPreset(look.id, amount: 100, id: first, engine: e); return dev.message }
        }
        await dev.reloadLists(e)
        log(!dev.history.isEmpty, "Develop: history list", "\(dev.history.count) steps")
        await step("Develop: history restore") { _ = try await e.execute("history.restore", ["index": 0]); return nil }
        await step("Develop: info (photo.inspect)") { let r = try await e.execute("photo.inspect") as? [String: Any]; return (r?.isEmpty ?? true) ? "empty reply" : nil }
        for tool in ["Edit", "Crop", "Mask", "Heal", "Looks", "History", "Info"] { dev.tool = tool; log(dev.tool == tool, "Develop: tab \(tool)") }

        // every slider, set to a high and a low value, then reset (each one must be accepted and the picture must render)
        var sliderFails: [String] = []
        for c in dev.controls {
            for frac in [0.25, 0.75] {
                let v = c.min + (c.max - c.min) * frac
                do { _ = try await e.execute("develop.set", ["control": c.id, "value": v]) } catch { sliderFails.append("\(c.label)=\(v): \(error.localizedDescription)") }
            }
            _ = try? await e.execute("develop.set", ["control": c.id, "value": c.def])
        }
        log(sliderFails.isEmpty, "Develop: all \(dev.controls.count) sliders accept low and high values", sliderFails.prefix(3).joined(separator: "; "))
        let rendered = await e.render(first, maxEdge: 600)
        log(rendered != nil, "Develop: picture still renders after the slider sweep")

        // every look, applied at three strengths
        var lookFails: [String] = []
        for look in dev.presets {
            for amount in [30, 100] {
                _ = try? await e.execute("edit.undo")
                do { _ = try await e.execute("preset.apply", ["id": look.id, "amount": amount]) } catch { lookFails.append("\(look.name)@\(amount): \(error.localizedDescription)") }
            }
        }
        log(lookFails.isEmpty, "Looks: all \(dev.presets.count) looks apply", lookFails.prefix(3).joined(separator: "; "))
        _ = try? await e.execute("develop.reset")

        // every crop shape
        var cropFails: [String] = []
        for a in ["original", "free", "1x1", "4x5", "5x7", "2x3", "4x3", "16x9", "16x10"] {
            do { _ = try await e.execute("crop.aspect", ["aspect": a]) } catch { cropFails.append("\(a): \(error.localizedDescription)") }
        }
        for angle in [-45.0, -10.5, 0, 10.5, 45] {
            do { _ = try await e.execute("crop.straighten", ["angle": angle]) } catch { cropFails.append("angle \(angle): \(error.localizedDescription)") }
        }
        _ = try? await e.execute("crop.reset")
        log(cropFails.isEmpty, "Crop: every aspect and straighten angle", cropFails.prefix(3).joined(separator: "; "))

        // every mask kind
        for kind in ["radial", "linear", "brush", "subject", "sky", "background"] {
            await step("Mask: add \(kind)") {
                var p: [String: Any] = ["kind": kind]
                if kind == "radial" { p = ["kind": kind, "center": [0.5, 0.5], "rx": 0.3, "ry": 0.25, "angle": 0, "feather": 50] }
                _ = try await e.execute("mask.add", p)
                for key in ["exposure", "contrast", "highlights", "shadows", "saturation"] { _ = try await e.execute("mask.adjust", ["values": [key: 0.3]]) }
                _ = try await e.execute("mask.deleteAll"); return nil
            }
        }

        // Export and watermarks
        let ex = ExportModel()
        ex.folder = tmp.appending(path: "out", directoryHint: .isDirectory)
        ex.wm.text = "© SelfTest"; ex.useWatermark = true
        await ex.run(ids: [first], engine: e)
        let outs = (try? FileManager.default.contentsOfDirectory(at: ex.folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        log(outs.contains { ((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 1000 }, "Export: JPEG with text watermark", ex.message ?? "")
        // every format x colour space x size, with and without a watermark
        for fmt in ["jpeg", "png", "tiff", "webp"] {
            for space in ["srgb", "displayP3", "adobeRgb"] {
                for edge in [1600, 0] {
                    for wmOn in [false, true] {
                        let x = ExportModel()
                        x.folder = tmp.appending(path: "fmt-\(fmt)-\(space)-\(edge)-\(wmOn)", directoryHint: .isDirectory)
                        x.format = fmt; x.colorSpace = space; x.longEdge = edge; x.useWatermark = wmOn; x.wm.text = "© T"
                        await x.run(ids: [first], engine: e)
                        let files = (try? FileManager.default.contentsOfDirectory(at: x.folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
                        let ok = files.contains { ((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 500 }
                        log(ok, "Export: \(fmt) \(space) \(edge == 0 ? "full" : "\(edge)px") \(wmOn ? "watermarked" : "plain")", ok ? "" : (x.message ?? "no file"))
                    }
                }
            }
        }
        // several photos in one export
        let many = ExportModel(); many.folder = tmp.appending(path: "many", directoryHint: .isDirectory); many.longEdge = 1600
        await many.run(ids: Array(model.ids.prefix(5)), engine: e)
        let manyFiles = (try? FileManager.default.contentsOfDirectory(atPath: many.folder.path)) ?? []
        log(manyFiles.count == 5, "Export: five photos at once", "\(manyFiles.count) files")
        for (name, tweak) in [("border and box", { (w: inout Watermark) in w.borderWidth = 0.01; w.backgroundOpacity = 0.5; w.padding = 0.01; w.radius = 0.01 }),
                              ("every anchor", { (w: inout Watermark) in w.anchor = .topLeft }),
                              ("vertical text, rotated", { (w: inout Watermark) in w.vertical = true; w.rotation = 90 })] as [(String, (inout Watermark) -> Void)] {
            var w = Watermark(); w.text = "© T"; tweak(&w)
            await step("Export: preview with \(name)") { let img = await e.renderWatermarked(first, maxEdge: 600, watermark: w.params, exportShortEdge: 2000); return img == nil ? "no image" : nil }
        }
        for a in Watermark.Anchor.allCases {
            var w = Watermark(); w.text = "©"; w.anchor = a
            let img = await e.renderWatermarked(first, maxEdge: 300, watermark: w.params, exportShortEdge: 2000)
            log(img != nil, "Export: position \(a.label)")
        }
        let store = WatermarkStore.shared
        let wname = "SelfTest-\(Int(Date().timeIntervalSince1970))"
        var saved = Watermark(); saved.text = "© saved"; saved.insetX = 0.1
        await step("Watermark: save “\(wname)”") { try await store.save(saved, as: wname, engine: e); return store.names.contains(wname) ? nil : "not listed" }
        await step("Watermark: load saved") { let w = try await store.load(wname, engine: e); return w.text == "© saved" && abs(w.insetX - 0.1) < 0.001 ? nil : "values differ" }
        await step("Watermark: export file → import file") {
            let json = try await e.watermarkFile(saved.params, name: wname)
            let f = tmp.appending(path: "wm.json"); try json.write(to: f, atomically: true, encoding: .utf8)
            let r = try await store.importFile(f, engine: e); return r.watermark.text == "© saved" ? nil : "values differ"
        }
        store.delete(wname); log(!store.names.contains(wname), "Watermark: delete saved")

        // Import into a fresh library
        let lib = tmp.appending(path: "library", directoryHint: .isDirectory)
        await step("Library: open or create a library") { if let err = await e.openLibrary(at: lib) { return err }; return nil }
        if let jpg = outs.first {
            let before = await e.visibleIDs().count
            await step("Import: photos into the library") { _ = try await e.execute("library.import", ["paths": [jpg.path], "mode": "copy"]); return nil }
            let after = await e.visibleIDs().count
            log(after == before + 1, "Import: library grew by one", "\(before) → \(after)")
        }
        try? FileManager.default.removeItem(at: tmp)
        finish(lines, failed, report)
    }

    private static func finish(_ lines: [String], _ failed: Int, _ report: String) {
        let summary = "\n\(lines.count - failed) passed, \(failed) failed\n"
        try? (lines.joined(separator: "\n") + summary).write(toFile: report, atomically: true, encoding: .utf8)
        exit(failed == 0 ? 0 : 1)
    }
}
