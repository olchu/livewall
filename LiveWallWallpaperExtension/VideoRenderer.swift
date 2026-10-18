import AVFoundation
import CoreMedia
import ObjectiveC
import os

/// Call AVSampleBufferDisplayLayer's private `_setDisallowsVideoLayerDisplayCompositing:`
/// (a BOOL setter Apple's WallpaperExtensionKit uses on every AVSBDL). Resolved via the
/// ObjC runtime so the private selector never appears in a header; a no-op if the API
/// ever disappears. Prevents the layer painting opaque black before its first frame.
private func setDisallowsVideoLayerDisplayCompositing(_ layer: CALayer, _ flag: Bool) {
    let sel = NSSelectorFromString("_setDisallowsVideoLayerDisplayCompositing:")
    guard layer.responds(to: sel),
          let imp = class_getMethodImplementation(type(of: layer), sel) else { return }
    typealias SetBoolFn = @convention(c) (AnyObject, Selector, ObjCBool) -> Void
    unsafeBitCast(imp, to: SetBoolFn.self)(layer, sel, ObjCBool(flag))
}

/// Phase 3 MVP renderer: single video, no adaptive quality tiers, no gapless
/// dual-reader preload (Phosphene's VideoRenderer has both — deferred, see
/// SPEC.md). Drives `AVSampleBufferDisplayLayer` manually via `AVAssetReader`
/// because `AVPlayerLayer` does not composite inside a remote `CAContext`.
final class VideoRenderer: @unchecked Sendable {
    private static let idCounter = OSAllocatedUnfairLock(initialState: 0)
    let debugID: Int = VideoRenderer.idCounter.withLock { $0 += 1; return $0 }

    let displayLayer: AVSampleBufferDisplayLayer
    let timebase: CMTimebase
    private let renderer: AVSampleBufferVideoRenderer
    private let asset: AVURLAsset
    private let videoTrack: AVAssetTrack
    private let queue = DispatchQueue(label: "com.ochurkin.LiveWall.wallpaper-extension.renderer", qos: .userInitiated)
    private var isRunning = true

    private var currentReader: AVAssetReader?
    private var currentOutput: AVAssetReaderTrackOutput?
    private var currentReaderYieldedSample = false
    private var isPaused = false

    /// Back-off before re-opening a reader that failed to start or yielded no
    /// samples (unreadable codec, corrupt file) — retrying immediately would
    /// spin the queue at 100% CPU. Doubles per consecutive failure, so a
    /// permanently bad file settles at one attempt a minute; resets once a
    /// reader plays through.
    private static let minRetryDelay: TimeInterval = 1
    private static let maxRetryDelay: TimeInterval = 60
    private var retryDelay = minRetryDelay

    // Gapless-ish looping: offset accumulates across loops so PTS/DTS stay
    // monotonically increasing instead of resetting to 0 (which would make the
    // control timebase see the new loop's frames as "in the past" and drop them).
    private var ptsOffset: CMTime = .zero
    private var lastEnqueuedEnd: CMTime = .zero

    static func create(rootLayer: CALayer, videoURL: URL) async throws -> VideoRenderer {
        let asset = AVURLAsset(url: videoURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [
                NSLocalizedDescriptionKey: "No video track found in \(videoURL.lastPathComponent)",
            ])
        }

        let displayLayer = AVSampleBufferDisplayLayer()
        displayLayer.videoGravity = .resizeAspectFill
        displayLayer.frame = rootLayer.bounds
        displayLayer.contentsScale = rootLayer.contentsScale
        displayLayer.isOpaque = true
        setDisallowsVideoLayerDisplayCompositing(displayLayer, true)

        return VideoRenderer(rootLayer: rootLayer, displayLayer: displayLayer, asset: asset, videoTrack: track)
    }

    private init(rootLayer: CALayer, displayLayer: AVSampleBufferDisplayLayer, asset: AVURLAsset, videoTrack: AVAssetTrack) {
        self.displayLayer = displayLayer
        self.renderer = displayLayer.sampleBufferRenderer
        self.asset = asset
        self.videoTrack = videoTrack

        var tb: CMTimebase?
        CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &tb)
        self.timebase = tb!
        CMTimebaseSetTime(timebase, time: .zero)
        // Rate stays 0 until start() — otherwise the timebase advances during the
        // async gap between init and start, making the first frames look "late".
        CMTimebaseSetRate(timebase, rate: 0.0)
        displayLayer.controlTimebase = timebase

        commitToRemoteContext { rootLayer.addSublayer(displayLayer) }
        log("  [Renderer #\(debugID)] created for \(asset.url.lastPathComponent)")
    }

    /// Decode and enqueue the first frame, then begin the feed loop.
    /// `onFirstFrameReady` fires once the context is actually displaying video —
    /// the caller gates its XPC reply on this so WallpaperAgent keeps compositing
    /// whatever it had until our content is real (never a black flash).
    func start(onFirstFrameReady: (@Sendable () -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self, isRunning else { onFirstFrameReady?(); return }

            CMTimebaseSetTime(timebase, time: .zero)
            ptsOffset = .zero
            lastEnqueuedEnd = .zero

            // On failure the feed loop sees no samples and retries with back-off.
            if beginReading(), let firstSample = currentOutput?.copyNextSampleBuffer() {
                currentReaderYieldedSample = true
                commitToRemoteContext { self.renderer.enqueue(firstSample) }
            }

            CMTimebaseSetRate(timebase, rate: 1.0)
            onFirstFrameReady?()
            feedFromCurrentReader()
        }
    }

    /// Re-frame to a new destination geometry (display reconnected at a different
    /// resolution, or a mode change).
    func resize(to destSize: CGSize, scale: CGFloat) {
        commitToRemoteContext {
            displayLayer.frame = CGRect(origin: .zero, size: destSize)
            displayLayer.contentsScale = scale
        }
    }

    func stop() {
        log("  [Renderer #\(debugID)] stopping")
        queue.sync {
            isRunning = false
            renderer.stopRequestingMediaData()
            currentReader?.cancelReading()
        }
        displayLayer.removeFromSuperlayer()
    }

    /// Freeze on the current frame and stop decoding — unlike `stop()`, the
    /// layer tree and remote CAContext stay live so `resume()` can pick back up
    /// without WallpaperAgent seeing a black flash or re-`acquire`.
    func pause() {
        queue.async { [weak self] in
            guard let self, isRunning, !isPaused else { return }
            isPaused = true
            renderer.stopRequestingMediaData()
            currentReader?.cancelReading()
            currentReader = nil
            currentOutput = nil
            CMTimebaseSetRate(timebase, rate: 0.0)
            log("  [Renderer #\(debugID)] paused")
        }
    }

    /// Resume after `pause()`. Restarts decoding from a fresh reader at the
    /// paused timeline position, same as a normal loop restart.
    func resume() {
        queue.async { [weak self] in
            guard let self, isRunning, isPaused else { return }
            isPaused = false
            ptsOffset = lastEnqueuedEnd
            guard beginReading() else {
                isPaused = true
                return
            }
            CMTimebaseSetRate(timebase, rate: 1.0)
            log("  [Renderer #\(debugID)] resumed")
            feedFromCurrentReader()
        }
    }

    /// Swap in a fresh reader on the same asset (used for every start, loop,
    /// resume, and recovery — a finished `AVAssetReader` can't be rewound).
    private func beginReading() -> Bool {
        guard let reader = try? AVAssetReader(asset: asset) else {
            log("  [Renderer #\(debugID)] failed to create reader")
            return false
        }
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else {
            log("  [Renderer #\(debugID)] reader failed to start: \(reader.error?.localizedDescription ?? "unknown")")
            return false
        }
        currentReader = reader
        currentOutput = output
        currentReaderYieldedSample = false
        return true
    }

    /// Run `action` on the queue after `retryDelay` (then back off further),
    /// unless a different reader was opened in the meantime (e.g. by
    /// `resume()`) — then the retry is stale.
    private func retryLater(_ action: @escaping (VideoRenderer) -> Void) {
        let reader = currentReader
        queue.asyncAfter(deadline: .now() + retryDelay) { [weak self] in
            guard let self, currentReader === reader else { return }
            action(self)
        }
        retryDelay = min(retryDelay * 2, Self.maxRetryDelay)
    }

    // MARK: - Playback loop

    private func feedFromCurrentReader() {
        renderer.requestMediaDataWhenReady(on: queue) { [weak self] in
            guard let self, isRunning else {
                self?.renderer.stopRequestingMediaData()
                return
            }

            if renderer.status == .failed {
                log("  [Renderer #\(debugID)] status failed: \(renderer.error?.localizedDescription ?? "unknown") — recovering")
                renderer.stopRequestingMediaData()
                retryLater { $0.restartFromZero() }
                return
            }
            if renderer.requiresFlushToResumeDecoding {
                renderer.flush()
            }

            while renderer.isReadyForMoreMediaData {
                if let sample = currentOutput?.copyNextSampleBuffer() {
                    let adjusted = offsetTimingForLoop(sample)
                    let pts = CMSampleBufferGetPresentationTimeStamp(adjusted)
                    let dur = CMSampleBufferGetDuration(adjusted)
                    if pts.isValid {
                        let sampleEnd = dur.isValid && dur > .zero ? CMTimeAdd(pts, dur) : CMTimeAdd(pts, CMTime(value: 1, timescale: 60))
                        if sampleEnd > lastEnqueuedEnd { lastEnqueuedEnd = sampleEnd }
                    }
                    renderer.enqueue(adjusted)
                    currentReaderYieldedSample = true
                } else {
                    // Reader exhausted — loop: swap in a fresh reader on the same asset.
                    // A reader that produced nothing at all is a failure, not a loop.
                    renderer.stopRequestingMediaData()
                    if currentReaderYieldedSample {
                        retryDelay = Self.minRetryDelay
                        queue.async { [weak self] in self?.loopToStart() }
                    } else {
                        log("  [Renderer #\(debugID)] reader yielded no samples — retrying in \(retryDelay)s")
                        retryLater { $0.loopToStart() }
                    }
                    return
                }
            }
        }
    }

    private func loopToStart() {
        guard isRunning, !isPaused else { return }
        // Normally lastEnqueuedEnd is ahead of the timebase; after a failed-read
        // stall the timebase has moved past it, and frames stamped earlier would
        // be dropped as late.
        ptsOffset = max(lastEnqueuedEnd, CMTimebaseGetTime(timebase))
        guard beginReading() else {
            retryLater { $0.loopToStart() }
            return
        }
        feedFromCurrentReader()
    }

    /// Hard reset after a decoder error — fresh timeline from 0, discard whatever
    /// was displayed (unlike a normal loop restart, which keeps the timeline
    /// continuous via ptsOffset).
    private func restartFromZero() {
        guard isRunning, !isPaused else { return }
        currentReader?.cancelReading()
        renderer.flush(removingDisplayedImage: true)
        guard beginReading() else {
            retryLater { $0.restartFromZero() }
            return
        }
        ptsOffset = .zero
        lastEnqueuedEnd = .zero
        CMTimebaseSetTime(timebase, time: .zero)
        CMTimebaseSetRate(timebase, rate: 1.0)
        feedFromCurrentReader()
    }

    /// Offset both DTS and PTS of a sample for loop continuation. Returns the
    /// original sample unchanged for the first loop (no copy needed).
    private func offsetTimingForLoop(_ sample: CMSampleBuffer) -> CMSampleBuffer {
        guard ptsOffset > .zero else { return sample }
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        let dts = CMSampleBufferGetDecodeTimeStamp(sample)
        let dur = CMSampleBufferGetDuration(sample)
        var timingInfo = CMSampleTimingInfo(
            duration: dur,
            presentationTimeStamp: pts.isValid ? CMTimeAdd(pts, ptsOffset) : pts,
            decodeTimeStamp: dts.isValid ? CMTimeAdd(dts, ptsOffset) : .invalid,
        )
        var adjusted: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sample, sampleTimingEntryCount: 1, sampleTimingArray: &timingInfo, sampleBufferOut: &adjusted)
        return adjusted ?? sample
    }
}
