import AppKit

/// Forwards system sleep/wake/screen events to PlaybackCoordinator.
final class SystemEventMonitor {
    private weak var coordinator: PlaybackCoordinator?
    private var observers: [Any] = []

    init(coordinator: PlaybackCoordinator) {
        self.coordinator = coordinator
    }

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        observers = [
            ws.addObserver(forName: NSWorkspace.willSleepNotification,
                           object: nil, queue: .main) { [weak self] _ in self?.coordinator?.handleSleep() },
            ws.addObserver(forName: NSWorkspace.didWakeNotification,
                           object: nil, queue: .main) { [weak self] _ in self?.coordinator?.handleWake() },
            ws.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                           object: nil, queue: .main) { [weak self] _ in self?.coordinator?.handleScreenSleep() },
            ws.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                           object: nil, queue: .main) { [weak self] _ in self?.coordinator?.handleScreenWake() },
        ]
    }

    func stop() {
        let ws = NSWorkspace.shared.notificationCenter
        observers.forEach { ws.removeObserver($0) }
        observers.removeAll()
    }
}
