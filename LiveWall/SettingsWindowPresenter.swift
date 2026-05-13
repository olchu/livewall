import AppKit
import SwiftUI

enum SettingsWindowPresenter {
    static let windowIdentifier = NSUserInterfaceItemIdentifier("LiveWall.SettingsWindow")
    private static var settingsWindow: NSWindow?

    static func openSettings() {
        NSApp.activate(ignoringOtherApps: true)

        if let window = settingsWindow ?? existingSettingsWindow {
            settingsWindow = window
            bringSettingsWindowToFront(window)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: SettingsView())
        configure(window)
        window.center()
        settingsWindow = window
    }

    static func prepareToOpenSettings() {
        openSettings()
    }

    static func configure(_ window: NSWindow) {
        window.identifier = windowIdentifier
        window.title = "LiveWall Settings"
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        bringSettingsWindowToFront(window)
    }

    private static var existingSettingsWindow: NSWindow? {
        NSApp.windows.first { $0.identifier == windowIdentifier }
    }

    private static func bringSettingsWindowToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.deminiaturize(nil)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }
}
