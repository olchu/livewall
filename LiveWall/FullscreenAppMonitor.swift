import AppKit

// Detects when a fullscreen app covers the desktop.
// CGWindowListCopyWindowInfo requires Screen Recording permission on macOS 10.15+;
// without it this monitor does nothing (no false positives).
final class FullscreenAppMonitor {
    var onFullscreenChanged: ((Bool) -> Void)?
    private var observers: [Any] = []

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        observers = [
            nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                           object: nil, queue: .main) { [weak self] _ in self?.evaluate() },
            nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                           object: nil, queue: .main) { [weak self] _ in self?.evaluate() },
        ]
    }

    func stop() {
        let nc = NSWorkspace.shared.notificationCenter
        observers.forEach { nc.removeObserver($0) }
        observers.removeAll()
    }

    private func evaluate() {
        onFullscreenChanged?(isFullscreenAppCovering())
    }

    private func isFullscreenAppCovering() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier != Bundle.main.bundleIdentifier,
              front.bundleIdentifier != "com.apple.finder" else { return false }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]],
              !list.isEmpty else {
            // No Screen Recording permission — return false to avoid false positives
            return false
        }

        let pid = front.processIdentifier
        for win in list {
            guard let winPID = win[kCGWindowOwnerPID as String] as? Int32, winPID == pid,
                  let layer = win[kCGWindowLayer as String] as? Int, layer == kCGNormalWindowLevel,
                  let bd = win[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let r = CGRect(x: bd["X"] ?? 0, y: bd["Y"] ?? 0,
                           width: bd["Width"] ?? 0, height: bd["Height"] ?? 0)
            if NSScreen.screens.contains(where: { r.width >= $0.frame.width && r.height >= $0.frame.height }) {
                return true
            }
        }
        return false
    }
}
