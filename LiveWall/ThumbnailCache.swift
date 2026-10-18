import AVFoundation
import CoreGraphics

/// Card thumbnails: a frame ~1s into each video (frame 0 is often black),
/// decoded off the main thread and kept in memory for the app's lifetime.
final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    private static let maximumSize = CGSize(width: 800, height: 450)
    private let cache: NSCache<NSURL, CGImage> = {
        let cache = NSCache<NSURL, CGImage>()
        cache.totalCostLimit = 256 * 1024 * 1024
        return cache
    }()

    private init() {}

    func thumbnail(for url: URL) async -> CGImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = Self.maximumSize
        // Any nearby keyframe will do — much cheaper than an exact-time decode.
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

        let image: CGImage
        if let frame = try? await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image {
            image = frame
        } else if let frame = try? await generator.image(at: .zero).image {
            image = frame // clips shorter than a second
        } else {
            return nil
        }
        cache.setObject(image, forKey: url as NSURL, cost: image.bytesPerRow * image.height)
        return image
    }
}
