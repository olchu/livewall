import AppKit
import Combine

final class WallpaperWindowManager: WallpaperWindowManaging {
    private var windows: [NSWindow] = []
    private var views: [VideoWallpaperView] = []
    private let settings: SettingsStore
    private var settingsCancellable: AnyCancellable?

    init(settings: SettingsStore = .shared) {
        self.settings = settings
        settingsCancellable = settings.$settings
            .map(\.playbackMode)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.setPlaybackMode(mode)
            }
    }

    func setupWallpaperWindows() {
        destroyWallpaperWindows()
        for screen in NSScreen.screens {
            let window = NSWindow.makeWallpaperWindow(screen: screen)
            let view = VideoWallpaperView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.autoresizingMask = [.width, .height]
            window.contentView = view
            if let url = settings.settings.wallpaperURL {
                view.loadVideo(url: url)
            }
            view.setGravity(settings.settings.playbackMode)
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
        views.forEach {
            $0.loadVideo(url: url)
            $0.setGravity(settings.settings.playbackMode)
        }
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

    private func setPlaybackMode(_ mode: PlaybackMode) {
        views.forEach { $0.setGravity(mode) }
    }
}
