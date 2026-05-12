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

        _ = settings.resolveAndStartAccessingWallpaper()
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
        wallpaperManager?.handleDisplayChange()
    }
}
