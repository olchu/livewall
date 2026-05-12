import AppKit

enum ScreenSaverInstaller {
    enum InstallError: LocalizedError {
        case bundledScreenSaverMissing
        case couldNotCreateDestinationDirectory

        var errorDescription: String? {
            switch self {
            case .bundledScreenSaverMissing:
                "LiveWallScreenSaver.saver was not found inside the app bundle."
            case .couldNotCreateDestinationDirectory:
                "Could not create the user Screen Savers folder."
            }
        }
    }

    static func installBundledScreenSaver() throws -> URL {
        guard let sourceURL = Bundle.main.builtInPlugInsURL?
            .appendingPathComponent("LiveWallScreenSaver.saver", isDirectory: true),
              FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw InstallError.bundledScreenSaverMissing
        }

        guard let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            throw InstallError.couldNotCreateDestinationDirectory
        }

        let screenSaversDirectory = libraryURL.appendingPathComponent("Screen Savers", isDirectory: true)
        try FileManager.default.createDirectory(
            at: screenSaversDirectory,
            withIntermediateDirectories: true
        )

        let destinationURL = screenSaversDirectory.appendingPathComponent(
            sourceURL.lastPathComponent,
            isDirectory: true
        )

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }
}
