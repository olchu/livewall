import AppKit

enum ScreenSaverInstaller {
    enum InstallError: LocalizedError {
        case bundledScreenSaverMissing

        var errorDescription: String? {
            "LiveWallScreenSaver.saver was not found inside the app bundle."
        }
    }

    // Opens the bundled .saver with Launch Services.
    // macOS shows its native "Install screen saver?" dialog — no sandbox permissions needed.
    static func installBundledScreenSaver() throws {
        guard let sourceURL = Bundle.main.builtInPlugInsURL?
            .appendingPathComponent("LiveWallScreenSaver.saver", isDirectory: true),
              FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw InstallError.bundledScreenSaverMissing
        }
        NSWorkspace.shared.open(sourceURL)
    }
}
