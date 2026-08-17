import Foundation

/// Build a WallpaperSettingsViewModelsXPC exposing LiveWall's current wallpaper
/// as a single selectable choice. See CodableShims.swift for how this crosses
/// into the real private XPC type without touching memory directly.
func buildSettingsViewModelsXPC() async -> AnyObject? {
    guard let videoURL = VideoSource.videoURL else {
        log("  [Settings] no video configured — empty groups")
        return makeEmptyGroupsResponse()
    }
    guard let thumbnailURL = await VideoSource.generateThumbnail() else {
        log("  [Settings] thumbnail generation failed — empty groups")
        return makeEmptyGroupsResponse()
    }

    let bundleID = Bundle.main.bundleIdentifier ?? "com.ochurkin.LiveWall.WallpaperExtension"
    let choiceID = ChoiceID(
        id: VideoSource.choiceID,
        descriptor: ChoiceIDDescriptor(
            provider: ChoiceProviderID(rawValue: bundleID),
            identifier: VideoSource.choiceID,
            files: [videoURL],
            configuration: Data(VideoSource.choiceID.utf8),
        ),
    )

    let choiceDescriptor = ChoiceDescriptor(
        id: choiceID,
        provider: ChoiceProviderID(rawValue: bundleID),
        identifier: VideoSource.choiceID,
        name: "LiveWall",
        localizedDescription: "Your LiveWall video wallpaper",
        thumbnail: .image(url: thumbnailURL),
        isDownloaded: true,
        options: [],
    )

    let item = SettingsItem(
        id: choiceID,
        localizedName: "LiveWall",
        thumbnail: .image(url: thumbnailURL),
        choice: choiceDescriptor,
        contentBadge: .video,
        showInTopLevel: true,
        sortOrder: 0,
        disposability: .none,
    )

    let group = SettingsGroup(
        id: GroupID(id: "livewall-wallpaper"),
        items: [item],
        localizedName: "LiveWall",
        disposability: .none,
        sortOrder: -100,
        sortID: GroupSortID(id: "com.apple.wallpaper.aerials"),
        allChoiceID: nil,
        shouldHideItemLabels: false,
        contextMenu: nil,
        thumbnail: nil,
    )

    let viewModel = SettingsViewModel(groups: [group], refreshPolicy: .default, isModificationDisabled: false)
    let viewModels = SettingsViewModels(desktop: viewModel, screenSaver: nil)
    return remapToRealXPC(viewModels)
}

/// Fallback: a WallpaperSettingsViewModelsXPC with empty groups (no video configured yet).
func makeEmptyGroupsResponse() -> AnyObject? {
    let empty = SettingsViewModels(
        desktop: SettingsViewModel(groups: [], refreshPolicy: .default, isModificationDisabled: false),
        screenSaver: nil,
    )
    return remapToRealXPC(empty)
}
