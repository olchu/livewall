import AppKit
import AVFoundation
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
    private weak var previewView: WallpaperPreviewView?
    private var thumbnailTask: Task<Void, Never>?
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

        // Wallpaper preview
        let pv = WallpaperPreviewView(frame: NSRect(x: 0, y: 0, width: 280, height: 100))
        previewView = pv
        let previewItem = NSMenuItem()
        previewItem.view = pv
        menu.addItem(previewItem)

        menu.addItem(.separator())

        pv.onSelectWallpaper = { [weak self] in
            self?.statusItem?.menu?.cancelTracking()
            self?.selectWallpaper()
        }

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
        menu.addItem(.separator())
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
        pauseOnBatteryItem?.state    = settings.settings.pauseOnBattery      ? .on : .off
        pauseOnFullscreenItem?.state = settings.settings.pauseWhenFullscreen  ? .on : .off
        pauseOnLockItem?.state       = settings.settings.pauseWhenLocked      ? .on : .off
        startAtLoginItem?.state      = loginItemManager.syncSettingsState(settings) ? .on : .off

        let snap = performance.snapshot()
        updateStat(cpuMenuItem, label: "CPU", value: snap.cpuFormatted)
        updateStat(ramMenuItem, label: "RAM", value: snap.ramFormatted)
        updateStat(gpuMenuItem, label: "GPU", value: "\(snap.gpuFormatted) (device)")

        updateThumbnail()
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

    private func updateThumbnail() {
        thumbnailTask?.cancel()
        guard let url = settings.settings.wallpaperURL else {
            previewView?.update(image: nil)
            return
        }
        thumbnailTask = Task { [weak self] in
            let asset = AVURLAsset(url: url)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 600, height: 300)
            guard let cgImage = try? await gen.image(at: .zero).image,
                  !Task.isCancelled else { return }
            let img = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            await MainActor.run {
                self?.previewView?.update(image: img)
            }
        }
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

// MARK: - Wallpaper preview thumbnail in menu

private final class WallpaperPreviewView: NSView {
    private let imageLayer = CALayer()
    private let selectButton = NSButton()
    private let versionLabel = NSTextField(labelWithString: "v.0.6")

    var onSelectWallpaper: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        layer?.cornerRadius = 8
        layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        layer?.masksToBounds = true
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        layer?.addSublayer(imageLayer)
        setupButton()
        setupVersionLabel()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupButton() {
        let title = NSAttributedString(
            string: "Select Wallpaper…",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 13, weight: .medium)
            ]
        )
        selectButton.attributedTitle = title
        selectButton.isBordered = false
        selectButton.wantsLayer = true
        selectButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        selectButton.layer?.borderColor = NSColor.white.cgColor
        selectButton.layer?.borderWidth = 1
        selectButton.layer?.cornerRadius = 6
        selectButton.target = self
        selectButton.action = #selector(buttonTapped)
        selectButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(selectButton)
        NSLayoutConstraint.activate([
            selectButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            selectButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            selectButton.widthAnchor.constraint(equalToConstant: 162),
            selectButton.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    private func setupVersionLabel() {
        versionLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        versionLabel.textColor = NSColor.white.withAlphaComponent(0.9)
        versionLabel.alignment = .right
        versionLabel.isSelectable = false
        versionLabel.wantsLayer = true
        versionLabel.layer?.shadowColor = NSColor.black.cgColor
        versionLabel.layer?.shadowOpacity = 0.45
        versionLabel.layer?.shadowRadius = 2
        versionLabel.layer?.shadowOffset = CGSize(width: 0, height: -1)
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(versionLabel)
        NSLayoutConstraint.activate([
            versionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            versionLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    @objc private func buttonTapped() {
        onSelectWallpaper?()
    }

    func update(image: NSImage?) {
        imageLayer.contents = image
        layer?.backgroundColor = image == nil
            ? NSColor.quaternaryLabelColor.cgColor
            : nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        CATransaction.commit()
    }
}
