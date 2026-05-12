import Foundation
import Combine

// Single source of truth for wallpaper playback state.
// Aggregates: user pause, battery, fullscreen app, screen lock, system sleep.
final class PlaybackCoordinator {
    private let manager: WallpaperWindowManaging
    private let settings: SettingsStore

    private var userPaused   = false
    private var sleeping     = false  // system or screen sleep — always overrides settings
    private var onBattery    = false
    private var fullscreen   = false
    private var locked       = false

    private var powerMonitor:      PowerModeMonitor?
    private var fullscreenMonitor: FullscreenAppMonitor?
    private var settingsCancellable: AnyCancellable?

    init(manager: WallpaperWindowManaging, settings: SettingsStore = .shared) {
        self.manager  = manager
        self.settings = settings
    }

    func start() {
        let power = PowerModeMonitor()
        power.onBatteryChanged = { [weak self] on in self?.onBattery = on; self?.apply() }
        onBattery = power.isOnBattery
        power.start()
        powerMonitor = power

        let fs = FullscreenAppMonitor()
        fs.onFullscreenChanged = { [weak self] on in self?.fullscreen = on; self?.apply() }
        fs.start()
        fullscreenMonitor = fs

        settingsCancellable = settings.$settings
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.apply() }

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(didLock),
                        name: .init("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(didUnlock),
                        name: .init("com.apple.screenIsUnlocked"), object: nil)
    }

    func stop() {
        powerMonitor?.stop()
        fullscreenMonitor?.stop()
        settingsCancellable = nil
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - System sleep/wake (always pause, regardless of settings)

    func handleSleep()       { sleeping = true;  manager.pause() }
    func handleScreenSleep() { sleeping = true;  manager.pause() }
    func handleWake()        { sleeping = false; manager.setupWallpaperWindows() }
    func handleScreenWake()  { sleeping = false; apply() }

    // MARK: - User control

    func toggleUserPause() { userPaused.toggle(); apply() }
    var isUserPaused: Bool { userPaused }

    // MARK: - Private

    @objc private func didLock()   { locked = true;  apply() }
    @objc private func didUnlock() { locked = false; apply() }

    private func apply() {
        guard !sleeping else { return }
        let s = settings.settings
        let shouldPause = userPaused
            || (s.pauseOnBattery      && onBattery)
            || (s.pauseWhenFullscreen && fullscreen)
            || (s.pauseWhenLocked     && locked)
        shouldPause ? manager.pause() : manager.resume()
    }
}
