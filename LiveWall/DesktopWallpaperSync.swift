import AppKit
import AVFoundation

enum DesktopWallpaperSync {
    private static let previewsDirectoryName = "DesktopPreviews"

    static func syncDesktopPicture(withVideoAt videoURL: URL) {
        Task {
            guard let imageURL = await makePreviewImage(from: videoURL) else { return }

            await MainActor.run {
                for screen in NSScreen.screens {
                    try? NSWorkspace.shared.setDesktopImageURL(imageURL, for: screen, options: [:])
                }
            }

            cleanupOldPreviewImages(keeping: imageURL)
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
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) else {
            return nil
        }
        let destinationURL: URL
        do {
            destinationURL = try previewImageURL()
        } catch {
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

    private static func previewImageURL() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return baseURL
            .appendingPathComponent("LiveWall", isDirectory: true)
            .appendingPathComponent(previewsDirectoryName, isDirectory: true)
            .appendingPathComponent("DesktopPreview-\(UUID().uuidString).jpg")
    }

    private static func cleanupOldPreviewImages(keeping currentURL: URL) {
        let directory = currentURL.deletingLastPathComponent()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let oldPreviews = files
            .filter { $0 != currentURL && $0.pathExtension.lowercased() == "jpg" }
            .sorted {
                let lhsDate = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }
            .dropFirst(2)

        for url in oldPreviews {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
