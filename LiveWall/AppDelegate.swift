import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var wallpaperManager: WallpaperWindowManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon, no Cmd+Tab appearance
        NSApp.setActivationPolicy(.accessory)

        let manager = WallpaperWindowManager()
        wallpaperManager = manager
        menuBarController = MenuBarController(manager: manager)

        manager.setupWallpaperWindows()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displaysChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        wallpaperManager?.destroyWallpaperWindows()
    }

    @objc private func displaysChanged() {
        wallpaperManager?.handleDisplayChange()
    }
}
