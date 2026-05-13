import AppKit
import UserNotifications
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
    private weak var startAtLoginItem: NSMenuItem?
    private weak var cpuMenuItem: NSMenuItem?
    private weak var ramMenuItem: NSMenuItem?
    private weak var gpuMenuItem: NSMenuItem?
    private var optimizationTask: Task<Void, Never>?
    private let notificationCenter = UNUserNotificationCenter.current()
    private let loginItemManager = LoginItemManager.shared

    init(manager: WallpaperWindowManaging,
         coordinator: PlaybackCoordinator,
         settings: SettingsStore = .shared) {
        self.manager     = manager
        self.coordinator = coordinator
        self.settings    = settings
        super.init()
        requestNotificationPermission()
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = makeStatusIcon()
        let menu = buildMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }

    private func makeStatusIcon() -> NSImage? {
        let image = NSImage(named: "statusbar")
            ?? NSImage(named: "StatusBarIcon")
            ?? NSImage(systemSymbolName: "play.rectangle.fill", accessibilityDescription: "LiveWall")
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        image?.accessibilityDescription = "LiveWall"
        return image
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu(title: "LiveWall Lite")

        menu.addItem(NSMenuItem(title: "Select Wallpaper…",
                                action: #selector(selectWallpaper),
                                keyEquivalent: "").then { $0.target = self })
        menu.addItem(NSMenuItem(title: "Reveal Optimized Videos",
                                action: #selector(revealOptimizedVideos),
                                keyEquivalent: "").then { $0.target = self })
        menu.addItem(NSMenuItem(title: "Install Screen Saver…",
                                action: #selector(installScreenSaver),
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
        startAtLoginItem = addToggle(to: menu, title: "Start at Login", action: #selector(toggleStartAtLogin), state: settings.settings.startAtLogin)
        menu.addItem(makeSettingsMenuItem())

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

    private func makeSettingsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        item.target = self
        return item
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        // Sync toggle states in case they changed programmatically
        pauseOnBatteryItem?.state    = settings.settings.pauseOnBattery      ? .on : .off
        pauseOnFullscreenItem?.state = settings.settings.pauseWhenFullscreen  ? .on : .off
        pauseOnLockItem?.state       = settings.settings.pauseWhenLocked      ? .on : .off
        startAtLoginItem?.state      = loginItemManager.syncSettingsState(settings) ? .on : .off

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

        switch optimizationChoice() {
        case .optimize:
            optimizeAndApplyWallpaper(from: url)
        case .original:
            applyWallpaper(url)
        case .cancel:
            return
        }
    }

    private enum OptimizationChoice {
        case optimize
        case original
        case cancel
    }

    private func optimizationChoice() -> OptimizationChoice {
        let alert = NSAlert()
        alert.messageText = "Optimize video for lower CPU?"
        alert.informativeText = "LiveWall can create an app-owned 1080p playback copy. The original video will not be changed."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Optimize Copy")
        alert.addButton(withTitle: "Use Original")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .optimize
        case .alertSecondButtonReturn:
            return .original
        default:
            return .cancel
        }
    }

    private func optimizeAndApplyWallpaper(from sourceURL: URL) {
        optimizationTask?.cancel()
        optimizationTask = Task { [weak self] in
            guard let self else { return }
            self.statusItem?.button?.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath",
                                                     accessibilityDescription: "Optimizing")
            do {
                let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccessing {
                        sourceURL.stopAccessingSecurityScopedResource()
                    }
                }
                let result = try await OptimizedVideoExporter.optimizedCopy(from: sourceURL)
                self.applyWallpaper(result.url)
                if !result.reusedExistingCopy {
                    self.notifyOptimizationSuccess(result.url)
                }
            } catch {
                self.applyWallpaper(sourceURL)
                self.showOptimizationError(error, fallbackURL: sourceURL)
            }
            self.statusItem?.button?.image = self.makeStatusIcon()
        }
    }

    private func applyWallpaper(_ url: URL) {
        settings.setWallpaperURL(url)
        DesktopWallpaperSync.syncDesktopPicture(withVideoAt: url)
        manager?.reloadWallpaper()
    }

    private func requestNotificationPermission() {
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notifyOptimizationSuccess(_ url: URL) {
        let content = UNMutableNotificationContent()
        content.title = "LiveWall"
        content.body = "Optimized copy created: \(url.lastPathComponent)"
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "optimized-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        notificationCenter.add(request)
    }

    private func showOptimizationError(_ error: Error, fallbackURL: URL) {
        let alert = NSAlert(error: error)
        alert.messageText = "Could not optimize this video"
        alert.informativeText = "LiveWall is using the original video instead:\n\(fallbackURL.lastPathComponent)"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Reveal Original")

        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([fallbackURL])
        }
    }

    @objc private func revealOptimizedVideos() {
        do {
            let directory = try OptimizedVideoExporter.optimizedWallpapersDirectory()
            NSWorkspace.shared.open(directory)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Could not open optimized videos folder"
            alert.runModal()
        }
    }

    @objc private func installScreenSaver() {
        do {
            let url = try ScreenSaverInstaller.installBundledScreenSaver()
            let alert = NSAlert()
            alert.messageText = "LiveWall Screen Saver Installed"
            alert.informativeText = "Choose LiveWallScreenSaver in System Settings → Screen Saver to use the animated wallpaper while the screen saver is active."
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Reveal")

            if alert.runModal() == .alertSecondButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Could not install LiveWall Screen Saver"
            alert.runModal()
        }
    }

    @objc private func openSettings() {
        SettingsWindowPresenter.openSettings()
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

    @objc private func toggleStartAtLogin() {
        let enabled = !loginItemManager.isEnabled
        do {
            try loginItemManager.setEnabled(enabled)
            settings.settings.startAtLogin = loginItemManager.isEnabled
            startAtLoginItem?.state = settings.settings.startAtLogin ? .on : .off
        } catch {
            settings.settings.startAtLogin = loginItemManager.isEnabled
            startAtLoginItem?.state = settings.settings.startAtLogin ? .on : .off
            let alert = NSAlert(error: error)
            alert.messageText = "Could not update Start at Login"
            alert.runModal()
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
