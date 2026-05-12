import AppKit

extension NSWindow {
    static func makeWallpaperWindow(screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = true
        // Appear on every Space without being cycled or shown in Mission Control
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        return window
    }
}
