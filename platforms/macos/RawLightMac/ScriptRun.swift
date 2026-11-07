import AppKit

/// Timed walk through the real window, for performance work: `RAWLIGHT_SCRIPT=/folder/of/raws RAWLIGHT_SCRIPT_LOG=/path/log.txt RawLight`.
/// Starts from the welcome screen, makes a new library, imports, opens Develop, switches tabs, steps photos, opens Export and quits.
/// Every step logs a wall-clock time (to line up with a screen recording) and the main thread's stalls, which are what feels slow.
@MainActor enum ScriptRun {
    private static var log = ""
    private static var step = "start"
    private static var last = Date()
    private static var path = ""
    private static var t0 = Date()

    private static func note(_ s: String) {
        let line = String(format: "%.3f  %6.0f ms  %@\n", Date().timeIntervalSince1970, Date().timeIntervalSince(t0) * 1000, s)
        log += line
        try? log.write(toFile: path, atomically: true, encoding: .utf8)
    }
    private static func mark(_ name: String) { step = name; note("STEP \(name)") }

    static func run(folder: String, logPath: String, model: LibraryModel) async {
        path = logPath; t0 = Date(); last = Date()
        // Main-thread watchdog: a tick every 8 ms; a late tick is a frame the user saw freeze.
        Timer.scheduledTimer(withTimeInterval: 0.008, repeats: true) { _ in
            MainActor.assumeIsolated {
                let now = Date(), gap = now.timeIntervalSince(last) * 1000
                if gap > 60 { note(String(format: "HITCH %.0f ms during %@", gap, step)) }
                last = now
            }
        }
        func pause(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

        mark("welcome shown"); await pause(1.5)
        let dir = FileManager.default.temporaryDirectory.appending(path: "RawLight-ScriptLib-\(Int(Date().timeIntervalSince1970))")
        mark("new library"); await model.openLibrary(dir); await pause(1)

        let files = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).sorted()
            .filter { ["arw", "cr2", "cr3", "nef", "dng", "raf"].contains(($0 as NSString).pathExtension.lowercased()) }
            .prefix(8).map { folder + "/" + $0 }
        mark("import \(files.count) raw files")
        model.module = "Library"
        let tImport = Date()
        _ = try? await model.engine.execute("library.import", ["paths": Array(files), "mode": "copy"])
        await model.load()
        note(String(format: "import took %.0f ms, %d photos", Date().timeIntervalSince(tImport) * 1000, model.ids.count))
        mark("library grid (thumbnails loading)"); await pause(6)

        guard let first = model.ids.first else { note("NO PHOTOS"); NSApp.terminate(nil); return }
        mark("select + open develop (first)"); model.selection = [first]; await pause(1)
        let tDev = Date(); model.openDevelop(first)
        await pause(6)
        note(String(format: "develop settled after %.0f ms of waiting", Date().timeIntervalSince(tDev) * 1000))

        for tool in ["Crop", "Mask", "Heal", "Looks", "History", "Info", "Edit"] {
            mark("tab \(tool)"); model.toolRequest = tool; await pause(1.5)
        }
        mark("auto"); model.devAction?("auto"); await pause(2)
        mark("b&w"); model.devAction?("bw"); await pause(2)
        mark("undo"); model.devAction?("undo"); await pause(2)
        for i in 1...3 { mark("next photo \(i)"); model.step(1); await pause(3) }
        mark("export"); model.module = "Export"; await pause(5)
        mark("back to library"); model.module = "Library"; await pause(3)
        mark("done"); await pause(0.5)
        NSApp.terminate(nil)
    }
}
