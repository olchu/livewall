import AppKit

final class WallpaperWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        // Place window at the desktop layer — below Finder icons, above desktop background
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        // Appear on every Space without being cycled or shown in Mission Control
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
    }
}
