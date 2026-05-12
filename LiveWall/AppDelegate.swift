import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var wallpaperManager: WallpaperWindowManager?
    private var systemEventMonitor: SystemEventMonitor?
    private let settings: SettingsStore = .shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let manager = WallpaperWindowManager()
        wallpaperManager = manager
        menuBarController = MenuBarController(manager: manager)

        // Restore wallpaper from previous session via security-scoped bookmark
        _ = settings.resolveAndStartAccessingWallpaper()
        manager.setupWallpaperWindows()

        systemEventMonitor = SystemEventMonitor(manager: manager)
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
        wallpaperManager?.destroyWallpaperWindows()
        settings.stopAccessingWallpaper()
    }

    @objc private func displaysChanged() {
        wallpaperManager?.handleDisplayChange()
    }
}
