import AppKit
import Foundation
import QuartzCore

/// Pending per-surface teardown timers (see `invalidate`) — touched only from
/// `Lifecycle.queue`. Keyed by WallpaperID UUID: WallpaperAgent multiplexes the
/// live desktop, a Settings preview/thumbnail probe, and (eventually) the lock
/// screen through one connection, each with its own acquire/invalidate — a
/// SINGLE shared timer let a preview probe's invalidate tear down the live
/// desktop (confirmed on-device). See WallpaperState.swift.
private enum Lifecycle {
    static let queue = DispatchQueue(label: "com.ochurkin.LiveWall.wallpaper-extension.lifecycle")
    static var teardownTimers: [UUID: DispatchWorkItem] = [:]
    /// Grace between an invalidate and actually tearing down: a re-acquire
    /// (display wake, brief Space-switch flicker) cancels it. Without this,
    /// every transient invalidate→re-acquire would destroy and recreate the
    /// renderer — a visible black flash, the exact bug class this project
    /// exists to avoid.
    static let teardownGrace: TimeInterval = 15.0
}

/// Implements every method WallpaperAgent can call on us
/// (`WallpaperExtensionXPCProtocol`, declared in the bridging header).
/// `acquire` renders LiveWall's single configured video (see VideoSource.swift);
/// download/migrate/shuffle/debug/choice-add-remove are stubs since Phase 3 MVP
/// has exactly one fixed, always-available choice — no library management yet
/// (see SPEC.md).
final class WallpaperXPCHandler: NSObject, WallpaperExtensionXPCProtocol {
    var connectionPID: Int32 = 0
    var agentProxy: (any WallpaperExtensionProxyXPCProtocol)?

    /// Set the first time any protocol method is actually invoked. Used by
    /// the invalidation handler in WallpaperExtensionConfig to distinguish a
    /// connection that talked to us from one that was accepted then dropped
    /// without ever calling anything — input Phase 4's spiral-of-death
    /// detector will need.
    private(set) var didServeMethod = false

    private func markServed(_ method: String) {
        didServeMethod = true
        log("  [XPC] \(method) (pid: \(connectionPID))")
    }

    // MARK: Lifecycle

    func acquire(withId id: Any?, request: Any?, reply: @escaping (Any?, Error?) -> Void) {
        markServed("acquire")
        Lifecycle.queue.async { [self] in acquireBody(id: id, request: request, reply: reply) }
    }

    private func acquireBody(id: Any?, request: Any?, reply: @escaping (Any?, Error?) -> Void) {
        let (uuid, existing) = WallpaperState.shared.context(for: id)
        Lifecycle.teardownTimers[uuid]?.cancel()
        Lifecycle.teardownTimers[uuid] = nil

        var destSize = CGSize(width: 2560, height: 1440)
        var scaleFactor: CGFloat = 2.0
        if let reqObj = request as? NSObject {
            for child in Mirror(reflecting: reqObj).children {
                for prop in Mirror(reflecting: child.value).children where prop.label == "destination" {
                    for destProp in Mirror(reflecting: prop.value).children {
                        if destProp.label == "size", let size = destProp.value as? CGSize { destSize = size }
                        if destProp.label == "scaleFactor", let sf = destProp.value as? CGFloat { scaleFactor = sf }
                    }
                }
            }
        }

        guard let videoURL = VideoSource.videoURL else {
            log("  [acquire] no video configured")
            reply(nil, NSError(domain: "LiveWallWallpaperExtension", code: 1, userInfo: [NSLocalizedDescriptionKey: "No wallpaper video configured"]))
            return
        }

        // Re-acquire of the SAME surface (display wake, quick revisit): reuse its
        // existing context instead of tearing down and rebuilding. A DIFFERENT
        // surface (different UUID — e.g. a Settings preview probe) falls through
        // to CREATE below and gets its own context, never stealing this one's.
        if let existing {
            log("  [acquire] REUSE ctx=\(existing.contextId) uuid=\(uuid)")
            if let resized = WallpaperState.shared.updateGeometryIfChanged(destSize: destSize, scaleFactor: scaleFactor, for: uuid) {
                CATransaction.begin(); CATransaction.setDisableActions(true)
                resized.rootLayer.frame = CGRect(origin: .zero, size: destSize)
                resized.rootLayer.contentsScale = scaleFactor
                CATransaction.commit(); CATransaction.flush()
                resized.renderer?.resize(to: destSize, scale: scaleFactor)
            }
            guard let replyObj = createRemoteContextXPC(contextId: existing.contextId) else {
                reply(nil, NSError(domain: "LiveWallWallpaperExtension", code: 2, userInfo: nil)); return
            }
            reply(replyObj, nil)
            return
        }

        // First acquire for this surface: create a fresh remote CAContext.
        guard let caContextRaw = CAContext.remoteContext(), let caContext = caContextRaw as? CAContext, caContext.contextId != 0 else {
            log("  ERROR: remote CAContext creation failed")
            reply(nil, NSError(domain: "LiveWallWallpaperExtension", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create remote CAContext"]))
            return
        }

        let rootLayer = CALayer()
        rootLayer.frame = CGRect(origin: .zero, size: destSize)
        rootLayer.contentsScale = scaleFactor
        rootLayer.contentsGravity = .resizeAspectFill
        caContext.layer = rootLayer
        CATransaction.flush()

        guard let replyObj = createRemoteContextXPC(contextId: caContext.contextId) else {
            reply(nil, NSError(domain: "LiveWallWallpaperExtension", code: 2, userInfo: nil)); return
        }

        WallpaperState.shared.installContext(
            ActiveWallpaper(caContext: caContext, contextId: caContext.contextId, rootLayer: rootLayer, renderer: nil, destSize: destSize, scaleFactor: scaleFactor),
            for: uuid,
        )
        log("  [acquire] created context \(caContext.contextId) uuid=\(uuid)")

        // NB: the reply is DEFERRED until the renderer has a real frame composited.
        // WallpaperAgent only hosts our context once it receives this reply, and a
        // bare CALayer's `.contents` does not composite cross-process (only
        // IOSurface-backed sample buffers do) — replying before that paints black.
        Task {
            let renderer: VideoRenderer
            do {
                renderer = try await VideoRenderer.create(rootLayer: rootLayer, videoURL: videoURL, stillImage: nil)
            } catch {
                log("  [acquire] renderer create failed: \(error)")
                reply(replyObj, nil) // unblock the acquire regardless
                return
            }
            WallpaperState.shared.setRenderer(renderer, for: uuid)
            renderer.start(onFirstFrameReady: {
                reply(replyObj, nil)
            })
        }
    }

    func update(withId _: Any?, request: Any?, reply: @escaping (Error?) -> Void) {
        markServed("update")
        var presentationMode = "default"
        if let request, let mode = mirrorFindProperty("presentationMode", in: request) {
            presentationMode = enumCaseName(mode)
        }
        WallpaperState.shared.presentationMode = presentationMode
        // Play/pause policy lands in Phase 4 (PlaybackPolicy) — for now the
        // renderer always plays once started.
        reply(nil)
    }

    func invalidate(withId id: Any?, reply: @escaping (Error?) -> Void) {
        markServed("invalidate")
        Lifecycle.queue.async {
            let (uuid, _) = WallpaperState.shared.context(for: id)
            Lifecycle.teardownTimers[uuid]?.cancel()
            let item = DispatchWorkItem {
                Lifecycle.teardownTimers[uuid] = nil
                let torn = WallpaperState.shared.tearDown(uuid: uuid)
                log("  [teardown] grace fired uuid=\(uuid) → \(torn ? "stopped renderer + invalidated CAContext" : "nothing to tear down")")
            }
            Lifecycle.teardownTimers[uuid] = item
            Lifecycle.queue.asyncAfter(deadline: .now() + Lifecycle.teardownGrace, execute: item)
        }
        reply(nil)
    }

    func snapshot(withId id: Any?, reply: @escaping (Any?, Error?) -> Void) {
        markServed("snapshot")
        // Stub: no IOSurface snapshot yet, so the Settings picker's live preview
        // during transitions may lag the static thumbnail. Deferred — see SPEC.md.
        reply(nil, nil)
    }

    // MARK: Settings

    func provideSettingsViewModels(withContentTypes types: Any?, reply: @escaping (Any?, Error?) -> Void) {
        markServed("provideSettingsViewModels")
        Task {
            if let result = await buildSettingsViewModelsXPC() {
                reply(result, nil)
            } else {
                reply(makeEmptyGroupsResponse(), nil)
            }
        }
    }

    // MARK: Choices

    func addChoiceRequest(withChoiceRequest request: Any?, onBehalfOfProcess process: Any?, reply: @escaping (Any?, Error?) -> Void) {
        markServed("addChoiceRequest")
        reply(nil, nil)
    }

    func removeChoiceRequest(withChoiceRequest request: Any?, reply: @escaping (Error?) -> Void) {
        markServed("removeChoiceRequest")
        reply(nil)
    }

    func selectedChoicesDidChange(for id: Any?, reply: @escaping (Error?) -> Void) {
        markServed("selectedChoicesDidChange")
        reply(nil)
    }

    func invokeContextMenuAction(withMenuItemID menuItemID: Any?, groupItemID: Any?, reply: @escaping (Error?) -> Void) {
        markServed("invokeContextMenuAction")
        reply(nil)
    }

    // MARK: Downloads
    // The single fixed choice is always a local file already on disk.

    func isChoiceDownloaded(with choiceID: Any?, reply: @escaping (Bool, Error?) -> Void) {
        markServed("isChoiceDownloaded")
        reply(true, nil)
    }

    func download(withChoiceID choiceID: Any?, reply: @escaping (Error?) -> Void) -> Any? {
        markServed("download")
        reply(nil)
        return nil
    }

    func pauseDownload(for choiceID: Any?, reply: @escaping (Error?) -> Void) {
        markServed("pauseDownload")
        reply(nil)
    }

    func cancelDownload(for choiceID: Any?, reply: @escaping (Error?) -> Void) {
        markServed("cancelDownload")
        reply(nil)
    }

    func resumeDownload(for choiceID: Any?, reply: @escaping (Error?) -> Void) {
        markServed("resumeDownload")
        reply(nil)
    }

    func removeDownload(for choiceID: Any?, reply: @escaping (Error?) -> Void) {
        markServed("removeDownload")
        reply(nil)
    }

    // MARK: Migration

    func migrateSelectedChoice(for id: Any?, reply: @escaping (Any?, Error?) -> Void) {
        markServed("migrateSelectedChoice")
        reply(nil, nil)
    }

    func migrate(from: Any?, to: Any?, reply: @escaping (Error?) -> Void) {
        markServed("migrate")
        reply(nil)
    }

    // MARK: Shuffle

    func skipShuffledContent(withId id: Any?, reply: @escaping (Error?) -> Void) {
        markServed("skipShuffledContent")
        reply(nil)
    }

    func canSkipShuffledContent(withId id: Any?, reply: @escaping (Bool, Error?) -> Void) {
        markServed("canSkipShuffledContent")
        reply(false, nil)
    }

    // MARK: Debug & notifications

    func handleDebugRequest(for request: Any?, reply: @escaping (Any?, Error?) -> Void) {
        markServed("handleDebugRequest")
        reply(nil, nil)
    }

    func handleNotification(withNamed name: Any?, reply: @escaping (Error?) -> Void) {
        markServed("handleNotification")
        reply(nil)
    }
}

/// Recursively search a value's `Mirror` for a stored property with the given
/// label, to a shallow depth. Robust to the XPC wrapper nesting, unlike scanning
/// a stringified description.
private func mirrorFindProperty(_ label: String, in value: Any, depth: Int = 0) -> Any? {
    guard depth < 6 else { return nil }
    for child in Mirror(reflecting: value).children {
        if child.label == label { return child.value }
        if let found = mirrorFindProperty(label, in: child.value, depth: depth + 1) { return found }
    }
    return nil
}

/// Extract an enum case name from a value: `.idle` → `"idle"`,
/// `.suspended(reason)` → `"suspended"`.
private func enumCaseName(_ value: Any) -> String {
    let mirror = Mirror(reflecting: value)
    if mirror.displayStyle == .enum, let label = mirror.children.first?.label {
        return label
    }
    return String(describing: value)
}
