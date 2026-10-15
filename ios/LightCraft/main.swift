import Foundation

@_silgen_name("lightcraft_start")
private func lightcraft_start(_ libraryPath: UnsafePointer<CChar>) -> Int32

let documents = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Documents", isDirectory: true)
let library = documents.appendingPathComponent("LightCraft Library", isDirectory: true)
try? FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
let result = library.path.withCString { lightcraft_start($0) }
if result != 0 {
    NSLog("LightCraft iPad exited with status %d", result)
}
