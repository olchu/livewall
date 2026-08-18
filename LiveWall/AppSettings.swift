import Foundation

struct AppSettings: Codable {
    var wallpaperURL: URL?
    var startAtLogin: Bool

    static let `default` = AppSettings(
        wallpaperURL: nil,
        startAtLogin: false
    )
}
