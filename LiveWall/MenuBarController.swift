import AppKit
import UniformTypeIdentifiers

final class MenuBarController {
    private var statusItem: NSStatusItem?
    private weak var manager: WallpaperWindowManaging?
    private let settings: SettingsStore
    private var isPaused = false
    private weak var pauseMenuItem: NSMenuItem?

    init(manager: WallpaperWindowManaging, settings: SettingsStore = .shared) {
        self.manager = manager
        self.settings = settings
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "play.rectangle.fill",
                                            accessibilityDescription: "LiveWall")
        statusItem?.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu(title: "LiveWall Lite")

        menu.addItem(NSMenuItem(title: "Select Wallpaper…",
                                action: #selector(selectWallpaper),
                                keyEquivalent: "").then { $0.target = self })
        menu.addItem(.separator())

        let pauseItem = NSMenuItem(title: "Pause",
                                   action: #selector(togglePause),
                                   keyEquivalent: "")
        pauseItem.target = self
        pauseMenuItem = pauseItem
        menu.addItem(pauseItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit LiveWall",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        return menu
    }

    @objc private func selectWallpaper() {
        let panel = NSOpenPanel()
        panel.title = "Choose a wallpaper video"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        var types: [UTType] = [.mpeg4Movie, .quickTimeMovie]
        if let m4v = UTType(filenameExtension: "m4v") { types.append(m4v) }
        panel.allowedContentTypes = types

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.settings.wallpaperURL = url
        manager?.reloadWallpaper()
    }

    @objc private func togglePause() {
        isPaused.toggle()
        if isPaused {
            manager?.pause()
            pauseMenuItem?.title = "Resume"
        } else {
            manager?.resume()
            pauseMenuItem?.title = "Pause"
        }
    }
}

// MARK: - NSMenuItem builder helper
private extension NSMenuItem {
    func then(_ configure: (NSMenuItem) -> Void) -> NSMenuItem {
        configure(self)
        return self
    }
}
