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
    private let stillFrameLayer: CALayer
    private let asset: AVURLAsset
    private let videoTrack: AVAssetTrack
    private let queue = DispatchQueue(label: "com.ochurkin.LiveWall.wallpaper-extension.renderer", qos: .userInitiated)
    private var isRunning = true

    private var currentReader: AVAssetReader?
    private var currentOutput: AVAssetReaderTrackOutput?

    // Gapless-ish looping: offset accumulates across loops so PTS/DTS stay
    // monotonically increasing instead of resetting to 0 (which would make the
    // control timebase see the new loop's frames as "in the past" and drop them).
    private var ptsOffset: CMTime = .zero
    private var lastEnqueuedEnd: CMTime = .zero

    static func create(rootLayer: CALayer, videoURL: URL, stillImage: CGImage?) async throws -> VideoRenderer {
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

        return VideoRenderer(rootLayer: rootLayer, displayLayer: displayLayer, asset: asset, videoTrack: track, stillImage: stillImage)
    }

    private init(rootLayer: CALayer, displayLayer: AVSampleBufferDisplayLayer, asset: AVURLAsset, videoTrack: AVAssetTrack, stillImage: CGImage?) {
        self.displayLayer = displayLayer
        self.renderer = displayLayer.sampleBufferRenderer
        self.asset = asset
        self.videoTrack = videoTrack

        self.stillFrameLayer = CALayer()
        stillFrameLayer.frame = rootLayer.bounds
        stillFrameLayer.contentsGravity = .resizeAspectFill
        stillFrameLayer.contentsScale = rootLayer.contentsScale
        stillFrameLayer.opacity = 0
        stillFrameLayer.name = "livewall.stillFrame"

        var tb: CMTimebase?
        CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &tb)
        self.timebase = tb!
        CMTimebaseSetTime(timebase, time: .zero)
        // Rate stays 0 until start() — otherwise the timebase advances during the
        // async gap between init and start, making the first frames look "late".
        CMTimebaseSetRate(timebase, rate: 0.0)
        displayLayer.controlTimebase = timebase

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rootLayer.addSublayer(displayLayer)
        rootLayer.addSublayer(stillFrameLayer)
        if let stillImage, let stillBuffer = makeStillSampleBuffer(from: stillImage) {
            Self.setDisplayImmediately(stillBuffer)
            renderer.enqueue(stillBuffer)
        }
        CATransaction.commit()
        // flush() (not just commit()) pushes the layer tree to the render server for
        // a REMOTE context — without it the still never reaches WindowServer.
        CATransaction.flush()
        log("  [Renderer #\(debugID)] created for \(asset.url.lastPathComponent)")
    }

    /// Decode and enqueue the first frame, then begin the feed loop.
    /// `onFirstFrameReady` fires once the context is actually displaying video —
    /// the caller gates its XPC reply on this so WallpaperAgent keeps compositing
    /// whatever it had until our content is real (never a black flash).
    func start(onFirstFrameReady: (@Sendable () -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { onFirstFrameReady?(); return }
            guard isRunning, let reader = try? AVAssetReader(asset: asset) else { onFirstFrameReady?(); return }
            let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            reader.add(output)
            reader.startReading()

            CMTimebaseSetTime(timebase, time: .zero)

            if let firstSample = output.copyNextSampleBuffer() {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                renderer.enqueue(firstSample)
                CATransaction.commit()
                CATransaction.flush()
            }

            currentReader = reader
            currentOutput = output
            ptsOffset = .zero
            lastEnqueuedEnd = .zero

            CMTimebaseSetRate(timebase, rate: 1.0)
            onFirstFrameReady?()
            feedFromCurrentReader()
        }
    }

    /// Re-frame to a new destination geometry (display reconnected at a different
    /// resolution, or a mode change).
    func resize(to destSize: CGSize, scale: CGFloat) {
        let bounds = CGRect(origin: .zero, size: destSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        displayLayer.contentsScale = scale
        stillFrameLayer.frame = bounds
        stillFrameLayer.contentsScale = scale
        CATransaction.commit()
        CATransaction.flush()
    }

    func stop() {
        log("  [Renderer #\(debugID)] stopping")
        queue.sync {
            isRunning = false
            renderer.stopRequestingMediaData()
            currentReader?.cancelReading()
        }
        displayLayer.removeFromSuperlayer()
        stillFrameLayer.removeFromSuperlayer()
    }

    private static func setDisplayImmediately(_ sample: CMSampleBuffer) {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) else { return }
        for i in 0 ..< CFArrayGetCount(attachments) {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, i), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dict,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque(),
            )
        }
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
                queue.async { [weak self] in self?.restartFromZero() }
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
                } else {
                    // Reader exhausted — loop: swap in a fresh reader on the same asset.
                    renderer.stopRequestingMediaData()
                    queue.async { [weak self] in self?.loopToStart() }
                    return
                }
            }
        }
    }

    private func loopToStart() {
        guard isRunning else { return }
        ptsOffset = lastEnqueuedEnd
        guard let reader = try? AVAssetReader(asset: asset) else {
            log("  [Renderer #\(debugID)] failed to create reader for loop restart")
            return
        }
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.startReading()
        currentReader = reader
        currentOutput = output
        feedFromCurrentReader()
    }

    /// Hard reset after a decoder error — fresh timeline from 0, discard whatever
    /// was displayed (unlike a normal loop restart, which keeps the timeline
    /// continuous via ptsOffset).
    private func restartFromZero() {
        guard isRunning else { return }
        currentReader?.cancelReading()
        renderer.flush(removingDisplayedImage: true)
        guard let reader = try? AVAssetReader(asset: asset) else { return }
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.startReading()
        currentReader = reader
        currentOutput = output
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
