import Foundation

/// Watches for LiveWall.app announcing a new wallpaper video. WallpaperAgent
/// only calls `acquire` again on its own triggers (display wake, Space
/// switch, re-picking "LiveWall" in System Settings) — it has no idea the
/// user just picked a different video, so without this, a change made while
/// LiveWall is already the active wallpaper source would sit invisible until
/// one of those triggers happened to fire.
///
/// Darwin notifications cross the sandbox boundary with no entitlement and no
/// live process needed on the sending end beyond the moment it posts — this
/// is the app announcing a fact, not a request that requires it to still be
/// running.
enum VideoSourceWatcher {
    private static let notificationName = "com.ochurkin.LiveWall.wallpaperChanged" as CFString

    static func start() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                guard let videoURL = VideoSource.videoURL else { return }
                log("  [VideoSourceWatcher] wallpaper changed → \(videoURL.lastPathComponent)")
                VideoSource.invalidateThumbnailCache()
                WallpaperState.shared.reloadAllRenderers(videoURL: videoURL)
            },
            notificationName,
            nil,
            .deliverImmediately
        )
    }
}
