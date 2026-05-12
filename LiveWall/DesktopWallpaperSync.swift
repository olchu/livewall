import AppKit
import AVFoundation

enum DesktopWallpaperSync {
    private static let imageFileName = "DesktopPreview.jpg"

    static func syncDesktopPicture(withVideoAt videoURL: URL) {
        Task {
            guard let imageURL = await makePreviewImage(from: videoURL) else { return }

            await MainActor.run {
                for screen in NSScreen.screens {
                    try? NSWorkspace.shared.setDesktopImageURL(imageURL, for: screen, options: [:])
                }
            }
        }
    }

    private static func makePreviewImage(from videoURL: URL) async -> URL? {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        let cgImage: CGImage
        do {
            cgImage = try await generator.image(at: time).image
        } catch {
            guard let fallback = try? await generator.image(at: .zero).image else {
                return nil
            }
            cgImage = fallback
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.92]),
              let destinationURL = previewImageURL() else {
            return nil
        }

        do {
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destinationURL, options: .atomic)
            return destinationURL
        } catch {
            return nil
        }
    }

    private static func previewImageURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("LiveWall", isDirectory: true)
            .appendingPathComponent(imageFileName)
    }
}
