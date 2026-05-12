import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var wallpaperManager: WallpaperWindowManager?
    private var playbackCoordinator: PlaybackCoordinator?
    private var systemEventMonitor: SystemEventMonitor?
    private let settings: SettingsStore = .shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let manager = WallpaperWindowManager()
        let coordinator = PlaybackCoordinator(manager: manager)
        wallpaperManager = manager
        playbackCoordinator = coordinator
        menuBarController = MenuBarController(manager: manager, coordinator: coordinator)

        if let url = settings.resolveAndStartAccessingWallpaper() {
            DesktopWallpaperSync.syncDesktopPicture(withVideoAt: url)
        }
        manager.setupWallpaperWindows()

        coordinator.start()

        systemEventMonitor = SystemEventMonitor(coordinator: coordinator)
        systemEventMonitor?.start()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displaysChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        systemEventMonitor?.stop()
        playbackCoordinator?.stop()
        wallpaperManager?.destroyWallpaperWindows()
        settings.stopAccessingWallpaper()
    }

    @objc private func displaysChanged() {
        if let url = settings.settings.wallpaperURL {
            DesktopWallpaperSync.syncDesktopPicture(withVideoAt: url)
        }
        wallpaperManager?.handleDisplayChange()
    }
}
