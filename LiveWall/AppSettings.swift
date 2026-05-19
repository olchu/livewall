import Foundation

struct AppSettings: Codable {
    var wallpaperURL: URL?
    var playbackMode: PlaybackMode
    var startAtLogin: Bool
    var batterySaverEnabled: Bool
    var pauseOnBattery: Bool
    var pauseWhenFullscreen: Bool
    var pauseWhenLocked: Bool
    var crossfadeEnabled: Bool
    var crossfadeDuration: Double

    static let `default` = AppSettings(
        wallpaperURL: nil,
        playbackMode: .fill,
        startAtLogin: false,
        batterySaverEnabled: false,
        pauseOnBattery: false,
        pauseWhenFullscreen: false,
        pauseWhenLocked: false,
        crossfadeEnabled: false,
        crossfadeDuration: 1.5
    )
}
