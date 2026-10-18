import Foundation
import UniformTypeIdentifiers

final class SettingsStore {
    static let shared = SettingsStore()

    private(set) var settings: AppSettings {
        didSet { save() }
    }

    /// The `wallpaper.<ext>` variants written to ~/Movies/LiveWall. Must match
    /// the readers' own lists (separate targets): VideoSource.videoURL and
    /// LiveWallScreenSaverView.
    static let supportedVideoExtensions = ["mp4", "mov", "m4v"]

    private let defaults = UserDefaults.standard
    private let settingsKey = "com.ochurkin.LiveWall.settings"
    private let bookmarkKey = "com.ochurkin.LiveWall.wallpaperBookmark"
    private let folderBookmarkKey = "com.ochurkin.LiveWall.libraryFolderBookmark"

    /// Darwin notification name the wallpaper extension listens for (see
    /// LiveWallWallpaperExtension/VideoSourceWatcher.swift) to hot-swap its
    /// renderers without waiting for WallpaperAgent to re-`acquire`. Darwin
    /// notifications cross the sandbox boundary with no entitlement needed —
    /// this is the only signal the app sends the extension; it never talks to
    /// a running LiveWall.app to get its state.
    private static let wallpaperChangedNotification = "com.ochurkin.LiveWall.wallpaperChanged" as CFString

    // Active security-scoped access tokens — must be stopped before app quits
    private var accessingURL: URL?
    private var accessingFolderURL: URL?

    private init() {
        if let data = defaults.data(forKey: settingsKey),
           let saved = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = saved
        } else {
            settings = .default
        }
        restoreBookmarks()
    }

    // MARK: - Bookmark-based file access

    /// Persists a user-picked URL as a security-scoped bookmark and begins access.
    /// URL is always set immediately; bookmark is best-effort for persistence across restarts.
    func setWallpaperURL(_ url: URL) {
        beginAccess(url, replacing: &accessingURL, bookmarkKey: bookmarkKey)
        settings.wallpaperURL = url
        copyToMoviesFolder(url, onlyIfChanged: false)
    }

    /// Persists the library folder the window lists videos from, same way.
    func setLibraryFolder(_ url: URL) {
        beginAccess(url, replacing: &accessingFolderURL, bookmarkKey: folderBookmarkKey)
        settings.libraryFolderURL = url
    }

    func stopAccessing() {
        accessingURL?.stopAccessingSecurityScopedResource()
        accessingURL = nil
        accessingFolderURL?.stopAccessingSecurityScopedResource()
        accessingFolderURL = nil
    }

    private func beginAccess(_ url: URL, replacing token: inout URL?, bookmarkKey key: String) {
        token?.stopAccessingSecurityScopedResource()
        token = url
        _ = url.startAccessingSecurityScopedResource()
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(bookmark, forKey: key)
        }
    }

    /// Resolves the stored bookmarks and begins access (on first use, i.e.
    /// launch). Saves settings only if a bookmark changed them.
    private func restoreBookmarks() {
        var restored = settings
        restored.libraryFolderURL = restoreBookmark(forKey: folderBookmarkKey, into: &accessingFolderURL, current: restored.libraryFolderURL)
        restored.wallpaperURL = restoreBookmark(forKey: bookmarkKey, into: &accessingURL, current: restored.wallpaperURL)
        if restored != settings { settings = restored }
        if let wallpaper = accessingURL {
            // Usually ~/Movies/LiveWall already holds this video and nothing is
            // copied (or hot-swapped); if the source was edited in place since,
            // refresh it.
            copyToMoviesFolder(wallpaper, onlyIfChanged: true)
        }
    }

    /// The URL to keep for a setting: its bookmark resolved and accessed; `nil`
    /// if the bookmark went stale (item moved or renamed — it's dropped); or
    /// `current` when there's no usable bookmark. Never prompts or mounts a
    /// volume, since this runs before the window appears.
    private func restoreBookmark(forKey key: String, into token: inout URL?, current: URL?) -> URL? {
        guard let data = defaults.data(forKey: key) else { return current }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return current
        }
        if stale {
            defaults.removeObject(forKey: key)
            return nil
        }
        _ = url.startAccessingSecurityScopedResource()
        token = url
        return url
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
