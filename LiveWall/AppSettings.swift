import Foundation

struct AppSettings: Codable {
    var wallpaperURL: URL?
    var playbackMode: PlaybackMode
    var startAtLogin: Bool
    var batterySaverEnabled: Bool
    var pauseOnBattery: Bool
    var pauseWhenFullscreen: Bool
    var pauseWhenLocked: Bool

    static let `default` = AppSettings(
        wallpaperURL: nil,
        playbackMode: .fill,
        startAtLogin: false,
        batterySaverEnabled: false,
        pauseOnBattery: false,
        pauseWhenFullscreen: false,
        pauseWhenLocked: false
    )
}
