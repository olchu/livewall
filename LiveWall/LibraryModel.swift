import AppKit
import Observation

/// State behind the library window (SPEC.md §3.1): the chosen folder, its
/// scanned sections, the selected card, and the current wallpaper.
@MainActor
@Observable
final class LibraryModel {
    private(set) var folderURL: URL?
    private(set) var sections: [LibrarySection] = []
    private(set) var hasScanned = false
    /// Standardized path of the current wallpaper — compared against every
    /// card on each render, so normalized once here rather than per card.
    private(set) var currentWallpaperPath: String?
    var selection: LibraryVideo?

    @ObservationIgnored private let store = SettingsStore.shared
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    init() {
        folderURL = store.settings.libraryFolderURL
        currentWallpaperPath = store.settings.wallpaperURL?.standardizedFileURL.path
    }

    var canSetSelectionAsWallpaper: Bool {
        guard let selection else { return false }
        return !isCurrentWallpaper(selection)
    }

    func isCurrentWallpaper(_ video: LibraryVideo) -> Bool {
        video.url.standardizedFileURL.path == currentWallpaperPath
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder with videos"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = folderURL
        guard panel.runModal() == .OK, let url = panel.url else { return }

        store.setLibraryFolder(url)
        folderURL = url
        selection = nil
        sections = []
        hasScanned = false
        rescan()
    }

    /// Re-read the folder (on launch, folder change, and app activation, so
    /// files added in Finder show up). Results from a superseded scan are dropped.
    func rescan() {
        guard let folder = folderURL else { return }
        scanTask?.cancel()
        scanTask = Task {
            let scanned = await Task.detached(priority: .userInitiated) { VideoLibrary.sections(in: folder) }.value
            guard !Task.isCancelled, folder == folderURL else { return }
            if scanned != sections { sections = scanned }
            hasScanned = true
            if let selection, !scanned.contains(where: { $0.videos.contains(selection) }) {
                self.selection = nil
            }
        }
    }

    func setSelectionAsWallpaper() {
        guard let selection, canSetSelectionAsWallpaper else { return }
        store.setWallpaperURL(selection.url)
        currentWallpaperPath = selection.url.standardizedFileURL.path
    }

    func openWallpaperSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
