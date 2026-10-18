import Foundation

/// Phase 4 (Resilience): pause every hosted renderer under thermal pressure,
/// resume once it clears. Lives entirely inside the extension process — no
/// dependency on LiveWall.app running, matching how the rest of this
/// extension works (WallpaperAgent hosts us whether or not the menu bar app
/// is open; see SPEC.md §3.5).
///
/// presentationMode-aware pausing is deferred: `update`'s request carries a
/// presentationMode enum case name (logged by WallpaperXPCHandler), but its
/// real values are unknown without on-device capture — guessing risks pausing
/// on the wrong signal.
final class PlaybackPolicy: NSObject {
    static let shared = PlaybackPolicy()

    private var thermalObserver: NSObjectProtocol?

    /// Last-applied decision, so a renderer created *after* the state changed
    /// (a fresh `acquire` while already throttled) starts paused instead of
    /// briefly playing before the next thermal notification catches it.
    private(set) var isPaused = false

    private override init() { super.init() }

    func start() {
        applyThermalState(ProcessInfo.processInfo.thermalState)
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: nil,
        ) { [weak self] _ in
            self?.applyThermalState(ProcessInfo.processInfo.thermalState)
        }
    }

    /// Sync a just-created renderer to the current policy decision.
    func apply(to renderer: VideoRenderer) {
        if isPaused { renderer.pause() }
    }

    private func applyThermalState(_ state: ProcessInfo.ThermalState) {
        isPaused = state == .serious || state == .critical
        log("  [PlaybackPolicy] thermalState=\(state) → \(isPaused ? "pause" : "resume")")
        if isPaused {
            WallpaperState.shared.forEachRenderer { $0.pause() }
        } else {
            WallpaperState.shared.forEachRenderer { $0.resume() }
        }
    }
}

extension ProcessInfo.ThermalState: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}
