import AppKit
import UniformTypeIdentifiers

final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private weak var manager: WallpaperWindowManaging?
    private let settings: SettingsStore
    private let performance = PerformanceMonitor()
    private var isPaused = false

    private weak var pauseMenuItem: NSMenuItem?
    private weak var cpuMenuItem: NSMenuItem?
    private weak var ramMenuItem: NSMenuItem?
    private weak var gpuMenuItem: NSMenuItem?

    init(manager: WallpaperWindowManaging, settings: SettingsStore = .shared) {
        self.manager = manager
        self.settings = settings
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

        let pauseItem = NSMenuItem(title: "Pause",
                                   action: #selector(togglePause),
                                   keyEquivalent: "")
        pauseItem.target = self
        pauseMenuItem = pauseItem
        menu.addItem(pauseItem)

        // Performance section
        menu.addItem(.separator())
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
