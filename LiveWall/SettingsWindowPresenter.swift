import AppKit

enum SettingsWindowPresenter {
    static let windowIdentifier = NSUserInterfaceItemIdentifier("LiveWall.SettingsWindow")

    static func prepareToOpenSettings() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            bringExistingSettingsWindowToFront()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            bringExistingSettingsWindowToFront()
        }
    }

    static func configure(_ window: NSWindow) {
        window.identifier = windowIdentifier
        window.title = "LiveWall Settings"
        window.collectionBehavior.insert(.moveToActiveSpace)
        bringSettingsWindowToFront(window)
    }

    private static func bringExistingSettingsWindowToFront() {
        guard let window = NSApp.windows.first(where: { $0.identifier == windowIdentifier }) else {
            return
        }
        bringSettingsWindowToFront(window)
    }

    private static func bringSettingsWindowToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.deminiaturize(nil)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }
}
