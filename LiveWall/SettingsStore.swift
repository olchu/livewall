import Foundation
import Combine
import UniformTypeIdentifiers

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var settings: AppSettings {
        didSet { save() }
    }

    /// The `wallpaper.<ext>` variants written to ~/Movies/LiveWall. Must match
    /// the readers' own lists (separate targets): VideoSource.videoURL and
    /// LiveWallScreenSaverView.
    static let supportedVideoExtensions = ["mp4", "mov", "m4v"]

    private let defaults = UserDefaults.standard
    private let settingsKey = "com.ochurkin.LiveWall.settings"
    private let bookmarkKey = "com.ochurkin.LiveWall.wallpaperBookmark"

    /// Darwin notification name the wallpaper extension listens for (see
    /// LiveWallWallpaperExtension/VideoSourceWatcher.swift) to hot-swap its
    /// renderers without waiting for WallpaperAgent to re-`acquire`. Darwin
    /// notifications cross the sandbox boundary with no entitlement needed —
    /// this is the only signal the app sends the extension; it never talks to
    /// a running LiveWall.app to get its state.
    private static let wallpaperChangedNotification = "com.ochurkin.LiveWall.wallpaperChanged" as CFString

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
        copyToMoviesFolder(url, onlyIfChanged: false)
    }

    /// Resolves the stored bookmark and begins access. Call on app launch.
    func resolveAndStartAccessingWallpaper() {
        stopAccessingWallpaper()
        guard let data = defaults.data(forKey: bookmarkKey) else { return }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return }

        if stale {
            // Bookmark went stale (file moved/renamed) — clear it
            defaults.removeObject(forKey: bookmarkKey)
            settings.wallpaperURL = nil
            return
        }

        _ = url.startAccessingSecurityScopedResource()
        accessingURL = url
        settings.wallpaperURL = url
        // This runs on every launch just to restore bookmark access. Usually
        // ~/Movies/LiveWall already holds this video and nothing is copied (or
        // hot-swapped); if the source was edited in place since, refresh it.
        copyToMoviesFolder(url, onlyIfChanged: true)
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

    // Copies the video into ~/Movies/LiveWall/ so the legacy .saver bundle and
    // the wallpaper extension (both sandboxed, separate containers) can read
    // it via their read-only temporary-exception entitlements, then tells the
    // extension to reload.
    private func copyToMoviesFolder(_ url: URL, onlyIfChanged: Bool) {
        let fm = FileManager.default
        guard let moviesURL = fm.urls(for: .moviesDirectory, in: .userDomainMask).first else { return }
        let liveWallDir = moviesURL.appendingPathComponent("LiveWall", isDirectory: true)

        let ext = Self.wallpaperExtension(for: url)
        let destURL = liveWallDir.appendingPathComponent("wallpaper.\(ext)")
        // Not a `wallpaper.<ext>` name, so readers never pick up a partial copy.
        let tempURL = liveWallDir.appendingPathComponent(".incoming-\(UUID().uuidString).\(ext)")

        DispatchQueue.global(qos: .utility).async {
            if onlyIfChanged, Self.isSameFile(url, destURL) { return }
            do {
                try fm.createDirectory(at: liveWallDir, withIntermediateDirectories: true)
                try fm.copyItem(at: url, to: tempURL)
                // rename(2) swaps the file in atomically: the extension (which
                // opens a fresh reader every loop) sees the old video or the new
                // one, never a missing or half-written file.
                guard rename(tempURL.path, destURL.path) == 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
            } catch {
                // Best-effort: the previous wallpaper stays in place.
                try? fm.removeItem(at: tempURL)
                return
            }
            for oldExt in Self.supportedVideoExtensions where oldExt != ext {
                try? fm.removeItem(at: liveWallDir.appendingPathComponent("wallpaper.\(oldExt)"))
            }
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName(Self.wallpaperChangedNotification),
                nil, nil, true
            )
        }
    }

    /// The `wallpaper.<ext>` extension the extension and `.saver` look for: a
    /// supported extension as-is, otherwise the container's canonical one — the
    /// open panel filters by type, so e.g. `clip.qt` or `clip.mpeg4` can be
    /// picked, and must not land under a name no reader checks.
    private static func wallpaperExtension(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if supportedVideoExtensions.contains(ext) { return ext }
        let type = UTType(filenameExtension: ext)
        return type?.conforms(to: .quickTimeMovie) == true ? "mov" : "mp4"
    }

    /// `copyItem` preserves size and modification date, so matching both means
    /// `dest` is already a copy of `source`.
    private static func isSameFile(_ source: URL, _ dest: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let a = try? source.resourceValues(forKeys: keys),
              let b = try? dest.resourceValues(forKeys: keys) else { return false }
        return a.fileSize == b.fileSize && a.contentModificationDate == b.contentModificationDate
    }
}
