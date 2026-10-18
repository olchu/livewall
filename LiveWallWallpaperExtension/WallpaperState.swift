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
    /// Bumped by every `startRenderer` call, so a slower, older create can't
    /// install over a newer one.
    var rendererGeneration = 0
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

    private let lock = OSAllocatedUnfairLock(initialState: [UUID: ActiveWallpaper]())

    private init() {}

    func context(for id: Any?) -> (uuid: UUID, context: ActiveWallpaper?) {
        let uuid = extractWallpaperUUID(fromID: id) ?? fallbackSurfaceUUID
        return (uuid, lock.withLock { $0[uuid] })
    }

    func installContext(_ context: ActiveWallpaper, for uuid: UUID) {
        lock.withLock { $0[uuid] = context }
    }

    /// Update stored geometry for a surface, returning it only if the geometry
    /// actually changed (so callers can skip a relayout on the common
    /// re-acquire with no change).
    func updateGeometryIfChanged(destSize: CGSize, scaleFactor: CGFloat, for uuid: UUID) -> ActiveWallpaper? {
        lock.withLock { contexts in
            guard var context = contexts[uuid] else { return nil }
            if context.destSize == destSize, context.scaleFactor == scaleFactor { return nil }
            context.destSize = destSize
            context.scaleFactor = scaleFactor
            contexts[uuid] = context
            return context
        }
    }

    func forEachRenderer(_ body: (VideoRenderer) -> Void) {
        let renderers = lock.withLock { $0.values.compactMap(\.renderer) }
        for renderer in renderers { body(renderer) }
    }

    /// Rebuild every hosted surface's renderer against a new source video —
    /// the user picked a different wallpaper in LiveWall.app while a surface
    /// (desktop and/or Lock Screen) was already live. Signaled via Darwin
    /// notification, not XPC — WallpaperAgent never asked us to reload, so
    /// there's no `acquire` to reply to; we just swap the layer tree's
    /// contents under the same, still-live remote CAContext. See
    /// VideoSourceWatcher.swift.
    func reloadAllRenderers(videoURL: URL) {
        let uuids = lock.withLock { Array($0.keys) }
        for uuid in uuids {
            Task {
                do {
                    try await startRenderer(for: uuid, videoURL: videoURL)
                } catch {
                    log("  [reload] renderer create failed for uuid=\(uuid): \(error)")
                }
            }
        }
    }

    /// Create a renderer for a surface, install it, start it, and sync it to
    /// the current `PlaybackPolicy` — the one path both `acquire` and
    /// `reloadAllRenderers` go through. The renderer it replaces keeps playing
    /// until then, and is stopped on install.
    ///
    /// Concurrent calls for one surface (two quick wallpaper picks, or a reload
    /// racing the first `acquire`) resolve to the newest: an outdated renderer,
    /// or one whose surface was torn down meanwhile, is stopped instead of
    /// installed. If creation fails the surface is left with no renderer, which
    /// is what makes the next `acquire` retry.
    func startRenderer(for uuid: UUID, videoURL: URL, onFirstFrameReady: (@Sendable () -> Void)? = nil) async throws {
        let ticket = lock.withLock { contexts -> (generation: Int, rootLayer: CALayer)? in
            guard var context = contexts[uuid] else { return nil }
            context.rendererGeneration += 1
            contexts[uuid] = context
            return (context.rendererGeneration, context.rootLayer)
        }
        guard let ticket else { onFirstFrameReady?(); return }

        let renderer: VideoRenderer
        do {
            renderer = try await VideoRenderer.create(rootLayer: ticket.rootLayer, videoURL: videoURL)
        } catch {
            swapRenderer(nil, for: uuid, generation: ticket.generation).previous?.stop()
            throw error
        }
        let (installed, previous) = swapRenderer(renderer, for: uuid, generation: ticket.generation)
        guard installed else {
            log("  [Renderer #\(renderer.debugID)] superseded before start — discarding")
            renderer.stop()
            onFirstFrameReady?()
            return
        }
        previous?.stop()
        renderer.start(onFirstFrameReady: onFirstFrameReady)
        PlaybackPolicy.shared.apply(to: renderer)
    }

    /// Install `renderer` if `generation` is still the surface's latest request,
    /// returning whether it was and the renderer it replaced.
    private func swapRenderer(_ renderer: VideoRenderer?, for uuid: UUID, generation: Int) -> (installed: Bool, previous: VideoRenderer?) {
        lock.withLock { contexts in
            guard var context = contexts[uuid], context.rendererGeneration == generation else { return (false, nil) }
            let previous = context.renderer
            context.renderer = renderer
            contexts[uuid] = context
            return (true, previous)
        }
    }

    /// Tear down only the ONE surface identified by `uuid` — never the whole
    /// dictionary. This is what stops a preview probe's invalidate from killing
    /// the live desktop.
    @discardableResult
    func tearDown(uuid: UUID) -> Bool {
        let removed = lock.withLock { $0.removeValue(forKey: uuid) }
        guard let removed else { return false }
        removed.renderer?.stop()
        invalidateRemoteContext(removed.caContext)
        return true
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
