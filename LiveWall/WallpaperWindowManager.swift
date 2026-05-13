import AppKit
import Combine

final class WallpaperWindowManager: WallpaperWindowManaging {
    private struct WallpaperWindowEntry {
        let window: NSWindow
        let view: VideoWallpaperView
    }

    private var windows: [NSWindow] = []
    private var views: [VideoWallpaperView] = []
    private var entries: [WallpaperWindowEntry] = []
    private let settings: SettingsStore
    private var settingsCancellable: AnyCancellable?
    private var playbackRequested = true
    private var visibilityRefreshWorkItem: DispatchWorkItem?
    private var windowOcclusionObserver: NSObjectProtocol?
    private var activeSpaceObserver: NSObjectProtocol?

    init(settings: SettingsStore = .shared) {
        self.settings = settings
        settingsCancellable = settings.$settings
            .map(\.playbackMode)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.setPlaybackMode(mode)
            }
        startVisibilityMonitoring()
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
            entries.append(WallpaperWindowEntry(window: window, view: view))
        }
        scheduleVisibilityRefresh()
    }

    func destroyWallpaperWindows() {
        windows.forEach { $0.close() }
        windows.removeAll()
        views.removeAll()
        entries.removeAll()
    }

    func reloadWallpaper() {
        guard let url = settings.settings.wallpaperURL else { return }
        views.forEach {
            $0.loadVideo(url: url)
            $0.setGravity(settings.settings.playbackMode)
        }
        applyEffectivePlayback()
    }

    func pause() {
        playbackRequested = false
        applyEffectivePlayback()
    }

    func resume() {
        playbackRequested = true
        applyEffectivePlayback()
    }

    func handleDisplayChange() {
        setupWallpaperWindows()
    }

    private func setPlaybackMode(_ mode: PlaybackMode) {
        views.forEach { $0.setGravity(mode) }
    }

    private func startVisibilityMonitoring() {
        windowOcclusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let self,
                let window = notification.object as? NSWindow,
                self.entries.contains(where: { $0.window === window })
            else { return }
            self.scheduleVisibilityRefresh()
        }

        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleVisibilityRefresh()
        }
    }

    private func scheduleVisibilityRefresh() {
        visibilityRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.applyEffectivePlayback()
        }
        visibilityRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func applyEffectivePlayback() {
        guard playbackRequested else {
            views.forEach { $0.pause() }
            return
        }

        let visibleEntries = entries.filter { isWindowVisibleOnActiveSpace($0.window) }
        let entriesToPlay = visibleEntries.isEmpty ? entries : visibleEntries

        for entry in entries {
            if entriesToPlay.contains(where: { $0.window === entry.window }) {
                entry.view.play()
            } else {
                entry.view.pause()
            }
        }
    }

    private func isWindowVisibleOnActiveSpace(_ window: NSWindow) -> Bool {
        window.isVisible && window.occlusionState.contains(.visible)
    }

    deinit {
        visibilityRefreshWorkItem?.cancel()
        if let windowOcclusionObserver {
            NotificationCenter.default.removeObserver(windowOcclusionObserver)
        }
        if let activeSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activeSpaceObserver)
        }
    }
}
