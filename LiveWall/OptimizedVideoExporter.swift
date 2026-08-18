import AVFoundation
import Foundation

enum OptimizedVideoExporter {
    struct ExportResult {
        let url: URL
        let reusedExistingCopy: Bool
    }

    enum ExportError: LocalizedError {
        case noCompatiblePreset
        case cannotCreateSession
        case noSupportedOutputType
        case exportFailed
        case cannotReadSourceMetadata

        var errorDescription: String? {
            switch self {
            case .noCompatiblePreset:
                return "No compatible AVFoundation export preset was found for this video."
            case .cannotCreateSession:
                return "Could not create an AVFoundation export session."
            case .noSupportedOutputType:
                return "No supported output file type was found for this video."
            case .exportFailed:
                return "The video export did not complete."
            case .cannotReadSourceMetadata:
                return "Could not read the selected video's file metadata."
            }
        }
    }

    static func exportOptimizedCopy(from sourceURL: URL) async throws -> URL {
        try await optimizedCopy(from: sourceURL).url
    }

    static func optimizedCopy(from sourceURL: URL) async throws -> ExportResult {
        let fingerprint = try sourceFingerprint(for: sourceURL)
        if let cachedURL = try cachedOptimizedCopy(for: fingerprint) {
            return ExportResult(url: cachedURL, reusedExistingCopy: true)
        }

        let asset = AVURLAsset(url: sourceURL)
        guard let preset = await preferredPreset(for: asset) else {
            throw ExportError.noCompatiblePreset
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ExportError.cannotCreateSession
        }

        let outputType = preferredOutputType(for: await session.compatibleFileTypes)
        guard let outputType else {
            throw ExportError.noSupportedOutputType
        }

        let outputURL = try makeOutputURL(fileExtension: fileExtension(for: outputType))
        try? FileManager.default.removeItem(at: outputURL)

        session.shouldOptimizeForNetworkUse = false
        // Cap to 30 fps: halves idle wake-ups and compositor CPU vs 60 fps sources.
        // 30 fps is imperceptible for a desktop wallpaper.
        let videoComposition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: asset)
        if CMTimeGetSeconds(videoComposition.frameDuration) < 1.0 / 30.0 {
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
            session.videoComposition = videoComposition
        }

        try await session.export(to: outputURL, as: outputType)
        try cacheOptimizedCopy(outputURL, for: fingerprint)
        return ExportResult(url: outputURL, reusedExistingCopy: false)
    }

    static func optimizedWallpapersDirectory(create: Bool = true) throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: create
        )
        let directory = baseURL
            .appendingPathComponent("LiveWall", isDirectory: true)
            .appendingPathComponent("OptimizedWallpapers", isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private static func preferredPreset(for asset: AVAsset) async -> String? {
        // HEVC presets use the dedicated Video Decode Engine on Apple Silicon/modern Intel,
        // dropping CPU decode cost to near-zero vs H.264 which shares CPU resources.
        let preferredPresets = [
            AVAssetExportPresetHEVC1920x1080,
            AVAssetExportPreset1920x1080,
            AVAssetExportPreset1280x720,
            AVAssetExportPresetMediumQuality,
            AVAssetExportPresetHighestQuality
        ]
        for preset in preferredPresets {
            if await AVAssetExportSession.compatibility(ofExportPreset: preset, with: asset, outputFileType: .mp4) {
                return preset
            }
            if await AVAssetExportSession.compatibility(ofExportPreset: preset, with: asset, outputFileType: .mov) {
                return preset
            }
        }
        return nil
    }

    private static func preferredOutputType(for types: [AVFileType]) -> AVFileType? {
        if types.contains(.mp4) { return .mp4 }
        if types.contains(.mov) { return .mov }
        return types.first
    }

    private static func fileExtension(for type: AVFileType) -> String {
        switch type {
        case .mp4: return "mp4"
        case .mov: return "mov"
        default: return "mov"
        }
    }

    private static func makeOutputURL(fileExtension: String) throws -> URL {
        let directory = try optimizedWallpapersDirectory()
        return directory.appendingPathComponent("wallpaper-\(UUID().uuidString).\(fileExtension)")
    }

    private static func sourceFingerprint(for sourceURL: URL) throws -> String {
        let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize else {
            throw ExportError.cannotReadSourceMetadata
        }
        return "\(sourceURL.lastPathComponent)|\(fileSize)"
    }

    private static func cachedOptimizedCopy(for fingerprint: String) throws -> URL? {
        var index = try loadIndex()
        guard let path = index[fingerprint] else { return nil }

        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            index.removeValue(forKey: fingerprint)
            try saveIndex(index)
            return nil
        }

        return url
    }

    private static func cacheOptimizedCopy(_ url: URL, for fingerprint: String) throws {
        var index = try loadIndex()
        index[fingerprint] = url.path
        try saveIndex(index)
    }

    private static func loadIndex() throws -> [String: String] {
        let url = try indexURL()
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private static func saveIndex(_ index: [String: String]) throws {
        let data = try JSONEncoder().encode(index)
        try data.write(to: try indexURL(), options: .atomic)
    }

    private static func indexURL() throws -> URL {
        try optimizedWallpapersDirectory()
            .appendingPathComponent("optimized-index.json")
    }

}
