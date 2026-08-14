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

enum LockScreenWallpaperManager {
    private static let dubaiAssetID = "00BA71CD-2C54-415A-A68A-8358E677D750"
    private static let targetDuration = CMTime(seconds: 360, preferredTimescale: 600)
    private static let appliedKey = "com.ochurkin.LiveWall.animatedLockScreenApplied"

    enum LockScreenError: LocalizedError {
        case requiresTahoe
        case aerialNotDownloaded
        case noVideoTrack
        case invalidDuration
        case cannotCreateExportSession
        case exportFailed
        case cannotActivateAerial
        case noBackup

        var errorDescription: String? {
            switch self {
            case .requiresTahoe:
                "Live Lock Screen requires macOS Tahoe 26 or later."
            case .aerialNotDownloaded:
                "Download and select the Dubai wallpaper in System Settings first."
            case .noVideoTrack:
                "The selected wallpaper does not contain a readable video track."
            case .invalidDuration:
                "The selected wallpaper has an invalid duration."
            case .cannotCreateExportSession:
                "Could not create the HEVC Lock Screen export session."
            case .exportFailed:
                "The Lock Screen video export did not complete."
            case .cannotActivateAerial:
                "The Dubai Aerial could not be activated as the system wallpaper."
            case .noBackup:
                "No original Dubai backup was found."
            }
        }
    }

    static var canRestore: Bool {
        FileManager.default.fileExists(atPath: backupURL.path)
    }

    static var isApplied: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: appliedKey) != nil {
            return defaults.bool(forKey: appliedKey)
        }

        // Migrate installations made before the state flag existed. A restored
        // original has the same size and modification date as its preserved copy.
        guard let current = try? aerialURL.resourceValues(
            forKeys: [.fileSizeKey, .contentModificationDateKey]
        ), let original = try? backupURL.resourceValues(
            forKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return false }

        return current.fileSize != original.fileSize
            || current.contentModificationDate != original.contentModificationDate
    }

    static func apply(videoURL: URL) async throws {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 else {
            throw LockScreenError.requiresTahoe
        }
        guard FileManager.default.fileExists(atPath: aerialURL.path) else {
            throw LockScreenError.aerialNotDownloaded
        }

        try createBackupIfNeeded()
        let preparedURL = try await prepareLockScreenVideo(from: videoURL)
        try replaceAerial(with: preparedURL)
        try activateDubaiAerialAsDesktopWallpaper()
        UserDefaults.standard.set(true, forKey: appliedKey)
        restartWallpaperAgent()
    }

    static func restore() throws {
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            throw LockScreenError.noBackup
        }
        try replaceAerial(with: backupURL, keepSource: true)
        UserDefaults.standard.set(false, forKey: appliedKey)
        restartWallpaperAgent()
    }

    private static var aerialsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/videos", isDirectory: true)
    }

    private static var aerialURL: URL {
        aerialsDirectory.appendingPathComponent("\(dubaiAssetID).mov")
    }

    private static var backupURL: URL {
        aerialsDirectory.appendingPathComponent("\(dubaiAssetID).livewall-original.mov")
    }

    private static var wallpaperStoreURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/com.apple.wallpaper/Store/Index.plist"
            )
    }

    private static func createBackupIfNeeded() throws {
        guard !FileManager.default.fileExists(atPath: backupURL.path) else { return }
        try FileManager.default.copyItem(at: aerialURL, to: backupURL)
    }

    private static func prepareLockScreenVideo(from sourceURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        guard let sourceTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw LockScreenError.noVideoTrack
        }
        let sourceDuration = try await asset.load(.duration)
        guard sourceDuration.isNumeric, sourceDuration > .zero else {
            throw LockScreenError.invalidDuration
        }

        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw LockScreenError.noVideoTrack
        }
        compositionTrack.preferredTransform = try await sourceTrack.load(.preferredTransform)

        var cursor = CMTime.zero
        while cursor < targetDuration {
            let remaining = targetDuration - cursor
            let segmentDuration = min(sourceDuration, remaining)
            try compositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: segmentDuration),
                of: sourceTrack,
                at: cursor
            )
            cursor = cursor + segmentDuration
        }

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHEVC1920x1080
        ) else {
            throw LockScreenError.cannotCreateExportSession
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LiveWall-LockScreen-\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: outputURL)
        session.shouldOptimizeForNetworkUse = false

        do {
            try await session.export(to: outputURL, as: .mov)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw LockScreenError.exportFailed
        }
        return outputURL
    }

    private static func replaceAerial(with sourceURL: URL, keepSource: Bool = false) throws {
        let temporaryURL = aerialsDirectory
            .appendingPathComponent(".\(dubaiAssetID).livewall-replacement.mov")
        try? FileManager.default.removeItem(at: temporaryURL)
        try FileManager.default.copyItem(at: sourceURL, to: temporaryURL)
        _ = try FileManager.default.replaceItemAt(aerialURL, withItemAt: temporaryURL)
        if !keepSource {
            try? FileManager.default.removeItem(at: sourceURL)
        }
    }

    private static func activateDubaiAerialAsDesktopWallpaper() throws {
        let data = try Data(contentsOf: wallpaperStoreURL)
        let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            options: [.mutableContainersAndLeaves],
            format: nil
        )
        guard let root = propertyList as? NSMutableDictionary,
              activateDubaiAerial(in: root) else {
            throw LockScreenError.cannotActivateAerial
        }

        let updatedData = try PropertyListSerialization.data(
            fromPropertyList: root,
            format: .binary,
            options: 0
        )
        try updatedData.write(to: wallpaperStoreURL, options: .atomic)
    }

    @discardableResult
    private static func activateDubaiAerial(in value: Any) -> Bool {
        var didChange = false

        if let dictionary = value as? NSMutableDictionary {
            if let desktop = dictionary["Desktop"] as? NSMutableDictionary,
               let idle = dictionary["Idle"] as? NSDictionary,
               let idleContent = idle["Content"],
               isDubaiAerialContent(idleContent) {
                desktop["Content"] = mutableCopy(of: idleContent)
                desktop["LastSet"] = Date()
                desktop["LastUse"] = Date()
                didChange = true
            }

            for child in dictionary.allValues {
                didChange = activateDubaiAerial(in: child) || didChange
            }
        } else if let array = value as? NSMutableArray {
            for child in array {
                didChange = activateDubaiAerial(in: child) || didChange
            }
        }

        return didChange
    }

    private static func isDubaiAerialContent(_ value: Any) -> Bool {
        guard let content = value as? NSDictionary,
              let choices = content["Choices"] as? NSArray else { return false }

        return choices.contains { choice in
            guard let choice = choice as? NSDictionary,
                  choice["Provider"] as? String == "com.apple.wallpaper.choice.aerials",
                  let configuration = choice["Configuration"] as? Data,
                  let decoded = try? PropertyListSerialization.propertyList(
                    from: configuration,
                    options: [],
                    format: nil
                  ),
                  let values = decoded as? NSDictionary else { return false }
            return values["assetID"] as? String == dubaiAssetID
        }
    }

    private static func mutableCopy(of value: Any) -> Any {
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: value,
            format: .binary,
            options: 0
        ) else { return value }

        return (try? PropertyListSerialization.propertyList(
            from: data,
            options: [.mutableContainersAndLeaves],
            format: nil
        )) ?? value
    }

    private static func restartWallpaperAgent() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["WallpaperAgent"]
        try? process.run()
    }
}
