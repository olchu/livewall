import AVFoundation
import Foundation

enum OptimizedVideoExporter {
    enum ExportError: LocalizedError {
        case noCompatiblePreset
        case cannotCreateSession
        case noSupportedOutputType
        case exportFailed

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
            }
        }
    }

    static func exportOptimizedCopy(from sourceURL: URL) async throws -> URL {
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

        try await session.export(to: outputURL, as: outputType)
        return outputURL
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
        let preferredPresets = [
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

}
