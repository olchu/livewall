import Foundation

/// Unified log (`NSLog`/`os_log`) redacts interpolated content as `<private>`
/// for sandboxed extensions, which makes Console.app useless for this
/// extension's diagnostics. Write to a plain file in the container instead —
/// same approach Phosphene uses for the same reason.
private let logURL: URL = {
    let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("extension.log")
}()

private let logDateFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

func log(_ message: String) {
    let line = "[\(logDateFormatter.string(from: Date()))] \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    if let handle = try? FileHandle(forWritingTo: logURL) {
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        handle.write(data)
    } else {
        try? data.write(to: logURL, options: .atomic)
    }
}
