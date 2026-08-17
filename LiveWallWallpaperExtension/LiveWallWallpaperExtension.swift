import AppKit
import ExtensionFoundation
import Foundation

/// Skeleton implementation of the `com.apple.wallpaper` ExtensionKit extension
/// point (see LiveWallWallpaperExtension/Info.plist). This is phase 1 of the
/// Lock Screen work described in SPEC.md: register with WallpaperAgent and
/// confirm the private WallpaperExtensionKit classes we'd eventually bridge to
/// are present, without touching any of them. XPC handling, rendering, and
/// snapshot generation come in later phases once this is confirmed to load
/// correctly on the real system.
@main
final class LiveWallWallpaperExtension: NSObject, AppExtension {
    override required init() {
        super.init()

        let frameworkPath = "/System/Library/PrivateFrameworks/WallpaperExtensionKit.framework/WallpaperExtensionKit"
        if dlopen(frameworkPath, RTLD_LAZY) != nil {
            log("INIT (PID: \(ProcessInfo.processInfo.processIdentifier)) — WallpaperExtensionKit loaded")
            verifyRuntimeLayout()
        } else {
            let err = String(cString: dlerror())
            log("INIT (PID: \(ProcessInfo.processInfo.processIdentifier)) — dlopen failed: \(err)")
        }
    }

    /// Read-only smoke test: confirms the private classes this extension will
    /// eventually bridge to exist under this OS build. No instances are
    /// created and no memory is touched — this only proves dlopen succeeded
    /// and the framework's Objective-C classes registered.
    private func verifyRuntimeLayout() {
        let expected = [
            "WallpaperRemoteContextXPC",
            "WallpaperSnapshotXPC",
            "WallpaperCreationRequestXPC",
            "WallpaperSettingsViewModelsXPC",
            "WallpaperIDXPC",
        ]
        let missing = expected.filter { objc_getClass($0) == nil }
        if missing.isEmpty {
            log("  [SelfCheck] Runtime layout OK — all \(expected.count) expected classes present")
        } else {
            log("  [SelfCheck] UNSUPPORTED RUNTIME — missing: \(missing.joined(separator: ", "))")
        }
    }

    var configuration: some AppExtensionConfiguration {
        WallpaperExtensionConfig()
    }
}
