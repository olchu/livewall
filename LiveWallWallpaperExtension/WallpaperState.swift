import Foundation
import os
import QuartzCore

/// One hosted wallpaper surface: the CAContext/layer tree WallpaperAgent hosts
/// in one CALayerHost.
struct ActiveWallpaper: @unchecked Sendable {
    let caContext: AnyObject // CAContext (private class, held as AnyObject)
    let contextId: UInt32
    let rootLayer: CALayer
    var renderer: VideoRenderer?
    var destSize: CGSize
    var scaleFactor: CGFloat
}

/// Fallback key for an acquire whose `id` carries no extractable WallpaperID UUID.
private let fallbackSurfaceUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

/// Contexts are keyed by WallpaperID UUID — WallpaperAgent multiplexes several
/// concurrent *surfaces* (the live desktop, a Settings-picker preview/thumbnail
/// probe, and eventually the lock screen) through the same XPC connection, each
/// with its own `acquire`/`invalidate` pair. Handing two different surfaces the
/// SAME `CAContext` makes the second steal the host from the first (it goes
/// gray) — confirmed on-device: a Settings preview probe's `acquire`+`invalidate`
/// was tearing down the live desktop's only context under the earlier
/// single-slot model. Phosphene calls this out explicitly (WallpaperState.swift
/// doc comments) as the reason it keys by UUID too; this is that fix, without
/// the further per-display fan-out Phosphene also does (single-display MVP).
final class WallpaperState: Sendable {
    static let shared = WallpaperState()

    private struct State: @unchecked Sendable {
        var contexts: [UUID: ActiveWallpaper] = [:]
        var presentationMode: String = "default"
        var activityState: String = "active"
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    private init() {}

    func context(for id: Any?) -> (uuid: UUID, context: ActiveWallpaper?) {
        let uuid = extractWallpaperUUID(fromID: id) ?? fallbackSurfaceUUID
        return (uuid, lock.withLock { $0.contexts[uuid] })
    }

    func installContext(_ context: ActiveWallpaper, for uuid: UUID) {
        lock.withLock { $0.contexts[uuid] = context }
    }

    func setRenderer(_ renderer: VideoRenderer?, for uuid: UUID) {
        lock.withLock { $0.contexts[uuid]?.renderer = renderer }
    }

    /// Update stored geometry for a surface, returning it only if the geometry
    /// actually changed (so callers can skip a relayout on the common
    /// re-acquire with no change).
    func updateGeometryIfChanged(destSize: CGSize, scaleFactor: CGFloat, for uuid: UUID) -> ActiveWallpaper? {
        lock.withLock { state in
            guard var context = state.contexts[uuid] else { return nil }
            if context.destSize == destSize, context.scaleFactor == scaleFactor { return nil }
            context.destSize = destSize
            context.scaleFactor = scaleFactor
            state.contexts[uuid] = context
            return context
        }
    }

    func forEachRenderer(_ body: (VideoRenderer) -> Void) {
        let renderers = lock.withLock { $0.contexts.values.compactMap(\.renderer) }
        for renderer in renderers { body(renderer) }
    }

    /// Tear down only the ONE surface identified by `uuid` — never the whole
    /// dictionary. This is what stops a preview probe's invalidate from killing
    /// the live desktop.
    @discardableResult
    func tearDown(uuid: UUID) -> Bool {
        let removed = lock.withLock { state -> ActiveWallpaper? in
            state.contexts.removeValue(forKey: uuid)
        }
        guard let removed else { return false }
        removed.renderer?.stop()
        invalidateRemoteContext(removed.caContext)
        return true
    }

    var presentationMode: String {
        get { lock.withLock { $0.presentationMode } }
        set { lock.withLock { $0.presentationMode = newValue } }
    }

    var activityState: String {
        get { lock.withLock { $0.activityState } }
        set { lock.withLock { $0.activityState = newValue } }
    }
}

/// Force the WindowServer to reclaim a remote `CAContext`. Dropping our Swift
/// reference (ARC) is not enough — the context is refcounted across processes
/// and WallpaperAgent's CALayerHost keeps its layer tree resident until this is
/// called explicitly.
func invalidateRemoteContext(_ caContext: AnyObject) {
    let sel = NSSelectorFromString("invalidate")
    guard let object = caContext as? NSObject, object.responds(to: sel) else { return }
    object.perform(sel)
}
