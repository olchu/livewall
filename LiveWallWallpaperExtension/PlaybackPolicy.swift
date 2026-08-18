import Foundation
import IOKit.ps

/// Phase 4 (Resilience): pause every hosted renderer under thermal pressure,
/// resume once it clears. Lives entirely inside the extension process — no
/// dependency on LiveWall.app running, matching how the rest of this
/// extension works (WallpaperAgent hosts us whether or not the menu bar app
/// is open; see SPEC.md §3.5).
///
/// Battery-aware and presentationMode-aware pausing are deferred:
/// - battery: the extension has no App Group to read the main app's
///   `pauseOnBattery` setting (sandboxed, separate container) — pausing
///   unconditionally on battery would silently diverge from that toggle's
///   default (off).
/// - presentationMode: `update`'s request carries a presentationMode enum
///   case name (see WallpaperXPCHandler), but its real values are unknown
///   without on-device capture — guessing risks pausing on the wrong signal.
final class PlaybackPolicy: NSObject {
    static let shared = PlaybackPolicy()

    private var thermalObserver: NSObjectProtocol?
    private var powerSource: PowerSourceObserver?

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

/// Minimal IOKit power-source-type observer, self-contained so the extension
/// doesn't need to reference the main app target's `PowerModeMonitor`
/// (separate PBXFileSystemSynchronizedRootGroup — see project layout in
/// CLAUDE.md). Not wired into `PlaybackPolicy` yet; kept ready for when an
/// App Group lets the extension read the user's `pauseOnBattery` setting.
final class PowerSourceObserver {
    var onBatteryChanged: ((Bool) -> Void)?
    private var runLoopSource: CFRunLoopSource?
    private var contextPtr: UnsafeMutableRawPointer?

    var isOnBattery: Bool {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        return type == kIOPSBatteryPowerValue
    }

    func start() {
        let ptr = Unmanaged.passRetained(self).toOpaque()
        contextPtr = ptr
        runLoopSource = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let observer = Unmanaged<PowerSourceObserver>.fromOpaque(ctx).takeUnretainedValue()
            let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
            let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
            observer.onBatteryChanged?(type == kIOPSBatteryPowerValue)
        }, ptr)?.takeRetainedValue()
        if let src = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
    }

    func stop() {
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode)
            runLoopSource = nil
        }
        if let ptr = contextPtr {
            Unmanaged<PowerSourceObserver>.fromOpaque(ptr).release()
            contextPtr = nil
        }
    }
}
