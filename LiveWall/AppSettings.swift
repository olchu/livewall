import Foundation

struct AppSettings: Codable, Equatable {
    var wallpaperURL: URL?
    var libraryFolderURL: URL?

    static let `default` = AppSettings(
        wallpaperURL: nil,
        libraryFolderURL: nil
    )
}
