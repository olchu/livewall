import Foundation
import IOKit.ps

final class PowerModeMonitor {
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
        // "Create" convention — take retained value
        runLoopSource = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let m = Unmanaged<PowerModeMonitor>.fromOpaque(ctx).takeUnretainedValue()
            let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
            let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
            m.onBatteryChanged?(type == kIOPSBatteryPowerValue)
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
            Unmanaged<PowerModeMonitor>.fromOpaque(ptr).release()
            contextPtr = nil
        }
    }
}
