import Foundation

// Codable mirrors of Apple's private WallpaperTypes structures, used to build a
// WallpaperSettingsViewModelsXPC without needing its (unavailable) headers — see
// `remapToRealXPC` below. Field names/order must match what the real class's
// `init(coder:)` expects to decode; a mismatch fails decoding safely (nil/error),
// not a crash, since this never touches raw memory.

struct SettingsViewModels: Codable {
    var desktop: SettingsViewModel?
    var screenSaver: SettingsViewModel?
}

struct SettingsViewModel: Codable {
    var groups: [SettingsGroup]
    var refreshPolicy: RefreshPolicy
    var isModificationDisabled: Bool
}

struct SettingsGroup: Codable {
    var id: GroupID
    var items: [SettingsItem]
    var localizedName: String
    var disposability: Disposability
    var sortOrder: Int
    var sortID: GroupSortID?
    var allChoiceID: ChoiceID?
    var shouldHideItemLabels: Bool?
    var contextMenu: ContextMenu?
    var thumbnail: Data?
}

/// Real type: WallpaperTypes.WallpaperDisposability with cases: none, removable, purgeable
enum Disposability: Codable {
    case none
    case removable
    case purgeable

    private enum CodingKeys: String, CodingKey {
        case none
        case removable
        case purgeable
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            _ = container.nestedContainer(keyedBy: EmptyCodingKeys.self, forKey: .none)
        case .removable:
            _ = container.nestedContainer(keyedBy: EmptyCodingKeys.self, forKey: .removable)
        case .purgeable:
            _ = container.nestedContainer(keyedBy: EmptyCodingKeys.self, forKey: .purgeable)
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.none) { self = .none } else if container.contains(.removable) { self = .removable } else if container.contains(.purgeable) { self = .purgeable } else { self = .none }
    }
}

struct GroupID: Codable {
    var id: String
}

struct GroupSortID: Codable {
    var id: String
}

struct ChoiceID: Codable {
    var id: String
    var descriptor: ChoiceIDDescriptor
}

struct ChoiceIDDescriptor: Codable {
    var provider: ChoiceProviderID
    var identifier: String
    var files: [URL]
    var configuration: Data
}

struct SettingsItem: Codable {
    var id: ChoiceID
    var localizedName: String
    var thumbnail: Thumbnail
    var choice: ChoiceDescriptor
    var contentBadge: ContentBadge
    var showInTopLevel: Bool
    var sortOrder: Int
    var disposability: Disposability
}

/// WallpaperSettingsItem.ContentBadge — cases: none, video, dynamic
enum ContentBadge: Codable {
    case none
    case video
    case dynamic

    private enum CodingKeys: String, CodingKey {
        case none
        case video
        case dynamic
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            _ = container.nestedContainer(keyedBy: EmptyCodingKeys.self, forKey: .none)
        case .video:
            _ = container.nestedContainer(keyedBy: EmptyCodingKeys.self, forKey: .video)
        case .dynamic:
            _ = container.nestedContainer(keyedBy: EmptyCodingKeys.self, forKey: .dynamic)
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.none) { self = .none } else if container.contains(.video) { self = .video } else if container.contains(.dynamic) { self = .dynamic } else { self = .none }
    }
}

/// WallpaperThumbnail — real enum has more cases (solidColor, shuffleColors, ...);
/// we only ever produce `.image`.
enum Thumbnail: Codable {
    case image(url: URL)

    private enum CodingKeys: String, CodingKey {
        case image
    }

    private enum ImageCodingKeys: String, CodingKey {
        case url
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var nested = container.nestedContainer(keyedBy: ImageCodingKeys.self, forKey: .image)
        switch self {
        case let .image(url):
            try nested.encode(url, forKey: .url)
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let nested = try container.nestedContainer(keyedBy: ImageCodingKeys.self, forKey: .image)
        let url = try nested.decode(URL.self, forKey: .url)
        self = .image(url: url)
    }
}

struct ChoiceDescriptor: Codable {
    var id: ChoiceID
    var provider: ChoiceProviderID
    var identifier: String
    var name: String?
    var localizedDescription: String
    var thumbnail: Thumbnail
    var isDownloaded: Bool
    var options: [WallpaperOption]
}

/// Placeholder for WallpaperOption — likely an enum; empty array is sufficient
/// for a single always-available choice.
struct WallpaperOption: Codable {}

/// Encodes as a plain string (singleValueContainer).
struct ChoiceProviderID: Codable {
    var rawValue: String

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }
}

enum RefreshPolicy: Codable {
    case `default`

    private enum CodingKeys: String, CodingKey {
        case `default`
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .default:
            _ = container.nestedContainer(keyedBy: EmptyCodingKeys.self, forKey: .default)
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.default) {
            self = .default
        } else {
            self = .default
        }
    }
}

struct ContextMenu: Codable {
    var items: [ContextMenuItem]
}

struct ContextMenuItem: Codable {
    var identifier: String
    var name: String
}

enum EmptyCodingKeys: CodingKey {}

/// NSObject wrapper that encodes SettingsViewModels using the same key as the real XPC type.
@objc(ShimViewModelsXPC)
class ShimViewModelsXPC: NSObject, NSSecureCoding {
    static let supportsSecureCoding = true
    let value: SettingsViewModels

    init(value: SettingsViewModels) {
        self.value = value
        super.init()
    }

    required init?(coder _: NSCoder) {
        fatalError("decode not needed")
    }

    func encode(with coder: NSCoder) {
        guard let archiver = coder as? NSKeyedArchiver else {
            log("  [ShimXPC] encode error: coder is not NSKeyedArchiver")
            return
        }
        do {
            try archiver.encodeEncodable(value, forKey: "WallpaperSettingsViewModels")
        } catch {
            log("  [ShimXPC] encode error: \(error)")
        }
    }
}

/// Archive via ShimViewModelsXPC, remap class name on unarchive to the real XPC type.
///
/// Secure coding cannot be required here: the whole point is to archive our own
/// `ShimViewModelsXPC` and decode it back as the private `WallpaperSettingsViewModelsXPC`
/// via `setClass(_:forClassName:)`, a substitution secure coding is designed to
/// forbid. This is safe because the archive is never persisted or received over
/// any boundary — it is produced and consumed in-process within this one function
/// from values we just constructed, so there is no untrusted input to defend
/// against. The decoded object is handed straight back to WallpaperAgent. Unlike
/// RuntimeHelpers.swift's ivar pokes, a wrong field here just fails to decode
/// (nil/error) — it cannot corrupt memory.
func remapToRealXPC(_ viewModels: SettingsViewModels) -> AnyObject? {
    let shimXPC = ShimViewModelsXPC(value: viewModels)

    let data: Data
    do {
        data = try NSKeyedArchiver.archivedData(withRootObject: shimXPC, requiringSecureCoding: false)
    } catch {
        log("  [Remap] Archive failed: \(error)")
        return nil
    }

    guard let realClass = objc_getClass("WallpaperSettingsViewModelsXPC") as? AnyClass else {
        log("  [Remap] WallpaperSettingsViewModelsXPC class not found")
        return nil
    }

    guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else {
        log("  [Remap] Failed to create unarchiver")
        return nil
    }
    unarchiver.requiresSecureCoding = false
    unarchiver.decodingFailurePolicy = .setErrorAndReturn
    unarchiver.setClass(realClass, forClassName: "ShimViewModelsXPC")

    let result = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
    if let error = unarchiver.error {
        log("  [Remap] Unarchive error: \(error)")
    }
    unarchiver.finishDecoding()

    if result == nil {
        log("  [Remap] Decoded result is nil")
    }
    return result as AnyObject?
}
