import AppKit

/// Handles system sleep/wake and screen sleep/wake events.
/// Pauses playback on sleep to save resources; resumes and recreates windows on wake.
final class SystemEventMonitor {
    private weak var manager: WallpaperWindowManaging?
    private var observers: [Any] = []

    init(manager: WallpaperWindowManaging) {
        self.manager = manager
    }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter

        observers = [
            workspace.addObserver(forName: NSWorkspace.willSleepNotification,
                                  object: nil, queue: .main) { [weak self] _ in
                self?.manager?.pause()
            },
            workspace.addObserver(forName: NSWorkspace.didWakeNotification,
                                  object: nil, queue: .main) { [weak self] _ in
                // Recreate windows — display configuration may have changed during sleep
                self?.manager?.setupWallpaperWindows()
            },
            workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                                  object: nil, queue: .main) { [weak self] _ in
                self?.manager?.pause()
            },
            workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                  object: nil, queue: .main) { [weak self] _ in
                self?.manager?.resume()
            },
        ]
    }

    func stop() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.forEach { workspace.removeObserver($0) }
        observers.removeAll()
    }
}
