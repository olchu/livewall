import AppKit

final class WallpaperWindowManager: WallpaperWindowManaging {
    private var windows: [NSWindow] = []
    private var views: [VideoWallpaperView] = []
    private let settings: SettingsStore

    init(settings: SettingsStore = .shared) {
        self.settings = settings
    }

    func setupWallpaperWindows() {
        destroyWallpaperWindows()
        for screen in NSScreen.screens {
            let window = NSWindow.makeWallpaperWindow(screen: screen)
            let view = VideoWallpaperView(frame: screen.frame)
            window.contentView = view
            if let url = settings.settings.wallpaperURL {
                view.loadVideo(url: url)
            }
            window.orderFront(nil)
            windows.append(window)
            views.append(view)
        }
    }

    func destroyWallpaperWindows() {
        windows.forEach { $0.close() }
        windows.removeAll()
        views.removeAll()
    }

    func reloadWallpaper() {
        guard let url = settings.settings.wallpaperURL else { return }
        views.forEach { $0.loadVideo(url: url) }
    }

    func pause() {
        views.forEach { $0.pause() }
    }

    func resume() {
        views.forEach { $0.play() }
    }

    func handleDisplayChange() {
        setupWallpaperWindows()
    }
}
