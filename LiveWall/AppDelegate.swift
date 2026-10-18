import AppKit
import ServiceManagement

/// LiveWall.app is a configurator, not a player: it picks a video and writes
/// it where the `com.apple.wallpaper` ExtensionKit extension can read it
/// (see LiveWallWallpaperExtension/VideoSource.swift). Actual playback — both
/// desktop and Lock Screen — is owned entirely by WallpaperAgent hosting that
/// extension, and keeps running whether or not this app is open. The app
/// renders no wallpaper itself; it's opened to pick one and quit.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        unregisterLegacyLoginItem()
        WallpaperExtensionRegistrar.bootstrap()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        SettingsStore.shared.stopAccessing()
    }

    /// Start at Login was removed with the menu bar (the app no longer runs in
    /// the background) — undo a login item an older version registered.
    private func unregisterLegacyLoginItem() {
        guard SMAppService.mainApp.status == .enabled else { return }
        try? SMAppService.mainApp.unregister()
    }
}
