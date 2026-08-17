import AVFoundation
import Foundation

/// Phase 3 MVP: a single, fixed video source rather than a full library. Reads
/// the same shared copy the legacy `.saver` bundle already reads
/// (`~/Movies/LiveWall/wallpaper.<ext>`), which the extension's entitlements
/// grant read-only access to (see LiveWallWallpaperExtension.entitlements).
/// A real multi-video library (VideoLibrary in Phosphene) is future work —
/// see SPEC.md.
enum VideoSource {
    static let choiceID = "com.ochurkin.LiveWall.currentWallpaper"

    static var videoURL: URL? {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies/LiveWall", isDirectory: true)
        return ["mp4", "mov", "m4v"]
            .map { directory.appendingPathComponent("wallpaper.\($0)") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static let thumbnailURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("thumbnail.jpg")
    }()

    /// Generate (or reuse a cached) JPEG thumbnail for the current video, in the
    /// extension's own sandbox container so WallpaperAgent's Settings picker can
    /// read it via the choice's declared `files`.
    static func generateThumbnail() async -> URL? {
        guard let videoURL else { return nil }
        if let existing = try? FileManager.default.attributesOfItem(atPath: thumbnailURL.path)[.modificationDate] as? Date,
           let source = try? FileManager.default.attributesOfItem(atPath: videoURL.path)[.modificationDate] as? Date,
           existing > source {
            return thumbnailURL
        }

        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 270)

        let cgImage: CGImage
        do {
            cgImage = try await generator.image(at: .zero).image
        } catch {
            log("  [Thumbnail] failed: \(error)")
            return nil
        }

        guard let dest = CGImageDestinationCreateWithURL(thumbnailURL as CFURL, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return thumbnailURL
    }
}
