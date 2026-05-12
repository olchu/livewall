import AppKit
import UniformTypeIdentifiers

final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private weak var manager: WallpaperWindowManaging?
    private weak var coordinator: PlaybackCoordinator?
    private let settings: SettingsStore
    private let performance = PerformanceMonitor()

    private weak var pauseMenuItem: NSMenuItem?
    private weak var pauseOnBatteryItem: NSMenuItem?
    private weak var pauseOnFullscreenItem: NSMenuItem?
    private weak var pauseOnLockItem: NSMenuItem?
    private weak var cpuMenuItem: NSMenuItem?
    private weak var ramMenuItem: NSMenuItem?
    private weak var gpuMenuItem: NSMenuItem?

    init(manager: WallpaperWindowManaging,
         coordinator: PlaybackCoordinator,
         settings: SettingsStore = .shared) {
        self.manager     = manager
        self.coordinator = coordinator
        self.settings    = settings
        super.init()
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "play.rectangle.fill",
                                            accessibilityDescription: "LiveWall")
        let menu = buildMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu(title: "LiveWall Lite")

        menu.addItem(NSMenuItem(title: "Select Wallpaper…",
                                action: #selector(selectWallpaper),
                                keyEquivalent: "").then { $0.target = self })
        menu.addItem(.separator())

        // Pause / Resume
        let pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        pauseMenuItem = pauseItem
        menu.addItem(pauseItem)

        menu.addItem(.separator())

        // Behaviour toggles
        pauseOnBatteryItem   = addToggle(to: menu, title: "Pause on Battery",       action: #selector(toggleBattery),    state: settings.settings.pauseOnBattery)
        pauseOnFullscreenItem = addToggle(to: menu, title: "Pause on Fullscreen App", action: #selector(toggleFullscreen), state: settings.settings.pauseWhenFullscreen)
        pauseOnLockItem      = addToggle(to: menu, title: "Pause on Screen Lock",    action: #selector(toggleLock),       state: settings.settings.pauseWhenLocked)

        menu.addItem(.separator())

        // Performance stats
        let cpuItem = makeStatItem("CPU:  —")
        let ramItem = makeStatItem("RAM:  —")
        let gpuItem = makeStatItem("GPU:  — (device)")
        cpuMenuItem = cpuItem
        ramMenuItem = ramItem
        gpuMenuItem = gpuItem
        menu.addItem(cpuItem)
        menu.addItem(ramItem)
        menu.addItem(gpuItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit LiveWall",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        return menu
    }

    private func addToggle(to menu: NSMenu, title: String, action: Selector, state: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = state ? .on : .off
        menu.addItem(item)
        return item
    }

    private func makeStatItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                         .foregroundColor: NSColor.secondaryLabelColor]
        )
        return item
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        // Sync toggle states in case they changed programmatically
        pauseOnBatteryItem?.state    = settings.settings.pauseOnBattery      ? .on : .off
        pauseOnFullscreenItem?.state = settings.settings.pauseWhenFullscreen  ? .on : .off
        pauseOnLockItem?.state       = settings.settings.pauseWhenLocked      ? .on : .off

        let snap = performance.snapshot()
        updateStat(cpuMenuItem, label: "CPU", value: snap.cpuFormatted)
        updateStat(ramMenuItem, label: "RAM", value: snap.ramFormatted)
        updateStat(gpuMenuItem, label: "GPU", value: "\(snap.gpuFormatted) (device)")
    }

    private func updateStat(_ item: NSMenuItem?, label: String, value: String) {
        guard let item else { return }
        let text = String(format: "%-4@ %@", label + ":", value)
        item.attributedTitle = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                         .foregroundColor: NSColor.secondaryLabelColor]
        )
    }

    // MARK: - Actions

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
        settings.setWallpaperURL(url)
        manager?.reloadWallpaper()
    }

    @objc private func togglePause() {
        coordinator?.toggleUserPause()
        pauseMenuItem?.title = coordinator?.isUserPaused == true ? "Resume" : "Pause"
    }

    @objc private func toggleBattery() {
        settings.settings.pauseOnBattery.toggle()
        pauseOnBatteryItem?.state = settings.settings.pauseOnBattery ? .on : .off
    }

    @objc private func toggleFullscreen() {
        settings.settings.pauseWhenFullscreen.toggle()
        pauseOnFullscreenItem?.state = settings.settings.pauseWhenFullscreen ? .on : .off
    }

    @objc private func toggleLock() {
        settings.settings.pauseWhenLocked.toggle()
        pauseOnLockItem?.state = settings.settings.pauseWhenLocked ? .on : .off
    }
}

// MARK: - NSMenuItem builder helper
private extension NSMenuItem {
    func then(_ configure: (NSMenuItem) -> Void) -> NSMenuItem {
        configure(self)
        return self
    }
}
