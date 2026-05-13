import Foundation
import Combine

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var settings: AppSettings {
        didSet { save() }
    }

    private let defaults = UserDefaults.standard
    private let sharedDefaults = UserDefaults(suiteName: "group.com.ochurkin.LiveWall")
    private let settingsKey = "com.ochurkin.LiveWall.settings"
    private let bookmarkKey = "com.ochurkin.LiveWall.wallpaperBookmark"
    private let sharedWallpaperBookmarkKey = "com.ochurkin.LiveWall.sharedWallpaperBookmark"
    private let sharedWallpaperPathKey = "com.ochurkin.LiveWall.sharedWallpaperPath"

    // Active security-scoped access token — must be stopped before app quits
    private var accessingURL: URL?

    private init() {
        if let data = defaults.data(forKey: settingsKey),
           let saved = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = saved
        } else {
            settings = .default
        }
    }

    // MARK: - Bookmark-based file access

    /// Persists a user-picked URL as a security-scoped bookmark and begins access.
    /// URL is always set immediately; bookmark is best-effort for persistence across restarts.
    func setWallpaperURL(_ url: URL) {
        stopAccessingWallpaper()
        settings.wallpaperURL = url
        accessingURL = url
        _ = url.startAccessingSecurityScopedResource()
        let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        if let bookmark {
            defaults.set(bookmark, forKey: bookmarkKey)
        }
        publishSharedWallpaperURL(url, bookmark: bookmark)
    }

    /// Resolves the stored bookmark and begins access. Call on app launch.
    func resolveAndStartAccessingWallpaper() -> URL? {
        stopAccessingWallpaper()
        guard let data = defaults.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }

        if stale {
            // Bookmark went stale (file moved/renamed) — clear it
            defaults.removeObject(forKey: bookmarkKey)
            clearSharedWallpaperURL()
            settings.wallpaperURL = nil
            return nil
        }

        _ = url.startAccessingSecurityScopedResource()
        accessingURL = url
        settings.wallpaperURL = url
        publishSharedWallpaperURL(url, bookmark: data)
        return url
    }

    func stopAccessingWallpaper() {
        accessingURL?.stopAccessingSecurityScopedResource()
        accessingURL = nil
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: settingsKey)
        }
    }

    private func publishSharedWallpaperURL(_ url: URL, bookmark: Data?) {
        if let bookmark {
            sharedDefaults?.set(bookmark, forKey: sharedWallpaperBookmarkKey)
        }
        sharedDefaults?.set(url.path, forKey: sharedWallpaperPathKey)
        copyToGroupContainer(url)
    }

    // Copies the video into ~/Movies/LiveWall/ so the legacyScreenSaver process
    // can read it via its container's Movies symlink (no entitlement needed there).
    private func copyToGroupContainer(_ url: URL) {
        let fm = FileManager.default
        guard let moviesURL = fm.urls(for: .moviesDirectory, in: .userDomainMask).first else { return }
        let liveWallDir = moviesURL.appendingPathComponent("LiveWall", isDirectory: true)

        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        let filename = "wallpaper.\(ext)"
        let destURL = liveWallDir.appendingPathComponent(filename)

        DispatchQueue.global(qos: .utility).async {
            do {
                if !fm.fileExists(atPath: liveWallDir.path) {
                    try fm.createDirectory(at: liveWallDir, withIntermediateDirectories: true)
                }
                // Remove any previous wallpaper files with other extensions
                for oldExt in ["mp4", "mov", "m4v"] where oldExt != ext {
                    let old = liveWallDir.appendingPathComponent("wallpaper.\(oldExt)")
                    try? fm.removeItem(at: old)
                }
                try? fm.removeItem(at: destURL)
                try fm.copyItem(at: url, to: destURL)
            } catch {
                // Best-effort: screensaver falls back to showing nothing
            }
        }
    }

    private func clearSharedWallpaperURL() {
        sharedDefaults?.removeObject(forKey: sharedWallpaperBookmarkKey)
        sharedDefaults?.removeObject(forKey: sharedWallpaperPathKey)
    }
}
