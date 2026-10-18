import AppKit
import Observation

/// State behind the library window (SPEC.md §3.1): the chosen folder, its
/// scanned sections, the selected card, and the current wallpaper.
@MainActor
@Observable
final class LibraryModel {
    private(set) var folderURL: URL?
    /// `nil` until the folder has been scanned at least once.
    private(set) var sections: [LibrarySection]?
    /// Standardized like `LibraryVideo.url`, so cards compare by plain equality.
    private(set) var currentWallpaperURL: URL?
    var selection: LibraryVideo?
    var isShowingSettings = false

    @ObservationIgnored private let store = SettingsStore.shared
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    init() {
        folderURL = store.settings.libraryFolderURL
        currentWallpaperURL = store.settings.wallpaperURL?.standardizedFileURL
    }

    var folderDisplayPath: String? {
        folderURL.map { ($0.path as NSString).abbreviatingWithTildeInPath }
    }

    var canSetSelectionAsWallpaper: Bool {
        guard let selection else { return false }
        return !isCurrentWallpaper(selection)
    }

    func isCurrentWallpaper(_ video: LibraryVideo) -> Bool {
        video.url == currentWallpaperURL
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
        sections = nil
        scanTask?.cancel()
        scanTask = nil
        rescan()
    }

    /// Re-read the folder (on launch, folder change, and app activation, so
    /// files added in Finder show up). A scan already running for the folder
    /// covers the request; a folder change drops the old scan's result.
    func rescan() {
        guard let folder = folderURL, scanTask == nil else { return }
        scanTask = Task {
            let scanned = await Task.detached(priority: .userInitiated) { VideoLibrary.sections(in: folder) }.value
            guard !Task.isCancelled else { return }
            scanTask = nil
            if scanned != sections { sections = scanned }
            if let selection, !scanned.contains(where: { $0.videos.contains(selection) }) {
                self.selection = nil
            }
        }
    }

    func setSelectionAsWallpaper() {
        guard let selection, canSetSelectionAsWallpaper else { return }
        store.setWallpaperURL(selection.url)
        currentWallpaperURL = selection.url
    }

    func installScreenSaver() {
        do {
            try ScreenSaverInstaller.installBundledScreenSaver()
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Could not install LiveWall Screen Saver"
            alert.runModal()
        }
    }

    func openWallpaperSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
