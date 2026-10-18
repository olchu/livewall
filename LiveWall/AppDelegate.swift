import AppKit

/// LiveWall.app is a configurator, not a player: it picks a video and writes
/// it where the `com.apple.wallpaper` ExtensionKit extension can read it
/// (see LiveWallWallpaperExtension/VideoSource.swift). Actual playback — both
/// desktop and Lock Screen — is owned entirely by WallpaperAgent hosting that
/// extension, and keeps running whether or not this app is open. The app
/// must not render anything itself.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private let settings: SettingsStore = .shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        menuBarController = MenuBarController()
        LoginItemManager.shared.syncSettingsState(settings)
        WallpaperExtensionRegistrar.bootstrap()

        settings.resolveAndStartAccessingWallpaper()
    }

    func applicationWillTerminate(_ notification: Notification) {
        settings.stopAccessingWallpaper()
    }
}
