import Foundation
import Combine

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var settings: AppSettings {
        didSet { save() }
    }

    private let defaults = UserDefaults.standard
    private let settingsKey = "com.ochurkin.LiveWall.settings"
    private let bookmarkKey = "com.ochurkin.LiveWall.wallpaperBookmark"

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
    func setWallpaperURL(_ url: URL) {
        stopAccessingWallpaper()
        guard let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        defaults.set(bookmark, forKey: bookmarkKey)
        settings.wallpaperURL = url
        _ = url.startAccessingSecurityScopedResource()
        accessingURL = url
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
            settings.wallpaperURL = nil
            return nil
        }

        _ = url.startAccessingSecurityScopedResource()
        accessingURL = url
        settings.wallpaperURL = url
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
}
