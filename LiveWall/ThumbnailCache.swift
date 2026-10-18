import AVFoundation
import CoreGraphics

/// Card thumbnails: a frame ~1s into each video (frame 0 is often black),
/// decoded off the main thread and kept in memory for the app's lifetime.
/// Concurrent requests for the same video share one decode.
actor ThumbnailCache {
    static let shared = ThumbnailCache()

    private static let maximumSize = CGSize(width: 800, height: 450)
    private let cache: NSCache<NSURL, CGImage> = {
        let cache = NSCache<NSURL, CGImage>()
        cache.totalCostLimit = 96 * 1024 * 1024 // ~65 thumbnails; a screen shows about a dozen
        return cache
    }()
    private var inFlight: [URL: Task<CGImage?, Never>] = [:]

    func thumbnail(for url: URL) async -> CGImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        if let pending = inFlight[url] { return await pending.value }

        let task = Task { await Self.decode(url) }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image {
            cache.setObject(image, forKey: url as NSURL, cost: image.bytesPerRow * image.height)
        }
        return image
    }

    private static func decode(_ url: URL) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maximumSize
        // Any nearby keyframe will do — much cheaper than an exact-time decode.
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

        if let frame = try? await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image {
            return frame
        }
        return try? await generator.image(at: .zero).image // clips shorter than a second
    }
}
