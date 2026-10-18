import AppKit
import ExtensionFoundation
import Foundation

/// Entry point of the `com.apple.wallpaper` ExtensionKit extension (see
/// LiveWallWallpaperExtension/Info.plist). WallpaperAgent hosts it for both
/// desktop and Lock Screen; it owns all wallpaper rendering — see SPEC.md §3.5.
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

        PlaybackPolicy.shared.start()
        VideoSourceWatcher.start()
    }

    /// Read-only smoke test: confirms the private classes this extension
    /// bridges to exist under this OS build. No instances are
    /// created and no memory is touched — this only proves dlopen succeeded
    /// and the framework's Objective-C classes registered.
    private func verifyRuntimeLayout() {
        let expected = WallpaperExtensionConfig.xpcTypeNames
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
