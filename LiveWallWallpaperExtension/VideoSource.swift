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
        // Must match SettingsStore.supportedVideoExtensions (app target).
        return ["mp4", "mov", "m4v"]
            .map { directory.appendingPathComponent("wallpaper.\($0)") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static let thumbnailURL: URL = containerDocumentsURL.appendingPathComponent("thumbnail.jpg")

    /// Generate (or reuse a cached) JPEG thumbnail for the current video, in the
    /// extension's own sandbox container so WallpaperAgent's Settings picker can
    /// read it via the choice's declared `files`. Cache reuse is keyed on the
    /// thumbnail simply existing — `VideoSourceWatcher` deletes it explicitly
    /// whenever the user picks a different video, which is the only event that
    /// should invalidate it. (An earlier version compared mtimes instead, but
    /// `SettingsStore`'s `copyItem` preserves the *source* video's original
    /// modification date — an older video copied in after a newer cached
    /// thumbnail already existed would keep the stale thumbnail forever.)
    static func generateThumbnail() async -> URL? {
        guard let videoURL else { return nil }
        if FileManager.default.fileExists(atPath: thumbnailURL.path) {
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

    /// Drop the cached thumbnail so the next `generateThumbnail()` call
    /// regenerates from the current video instead of reusing stale content.
    /// Called by `VideoSourceWatcher` whenever the user picks a different
    /// video.
    static func invalidateThumbnailCache() {
        try? FileManager.default.removeItem(at: thumbnailURL)
    }
}
