import SwiftUI

/// One 16:9 wallpaper card (SPEC.md §3.1): thumbnail, muted hover preview,
/// "Current" badge, accent outline when selected. Equatable on its inputs, so
/// a selection change re-renders only the two cards it affects.
struct VideoCard: View, Equatable {
    static let cornerRadius: CGFloat = 16
    /// Hover this long before the preview starts, so sweeping the pointer
    /// across a row doesn't spin up a player per card.
    private static let hoverDelay: Duration = .milliseconds(300)

    let video: LibraryVideo
    let isSelected: Bool
    let isCurrent: Bool
    let onSelect: () -> Void

    @State private var thumbnail: CGImage?
    @State private var isHovered = false
    @State private var isPlaying = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func == (lhs: VideoCard, rhs: VideoCard) -> Bool {
        lhs.video == rhs.video && lhs.isSelected == rhs.isSelected && lhs.isCurrent == rhs.isCurrent
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    }

    var body: some View {
        Button(action: onSelect) { card }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .task(id: isHovered) {
                guard isHovered else {
                    isPlaying = false
                    return
                }
                try? await Task.sleep(for: Self.hoverDelay)
                if !Task.isCancelled { isPlaying = true }
            }
            .task(id: video.url) {
                thumbnail = await ThumbnailCache.shared.thumbnail(for: video.url)
            }
            .accessibilityLabel(video.name)
            .accessibilityValue(isCurrent ? "Current wallpaper" : "")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var card: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                ZStack {
                    Rectangle().fill(.quaternary)
                    if let thumbnail {
                        Image(decorative: thumbnail, scale: 1)
                            .resizable()
                            .scaledToFill()
                    }
                    if isPlaying {
                        LoopingVideoView(url: video.url, cornerRadius: Self.cornerRadius)
                            .transition(.opacity)
                    }
                }
            }
            .overlay(alignment: .bottomLeading) {
                if isHovered {
                    Text(video.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.linearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .topLeading) {
                if isCurrent {
                    Label("Current", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(10)
                }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(isSelected ? Color.accentColor : .white.opacity(0.08), lineWidth: isSelected ? 3 : 1)
            }
            .shadow(color: .black.opacity(isHovered ? 0.45 : 0.25), radius: isHovered ? 14 : 8, y: 6)
            .scaleEffect(isHovered && !reduceMotion ? 1.02 : 1)
            .animation(.snappy(duration: 0.2), value: isHovered)
            .animation(.easeInOut(duration: 0.25), value: isPlaying)
            .contentShape(shape)
    }
}

extension VideoCard {
    /// A card wired to the library's selection and current wallpaper.
    init(video: LibraryVideo, model: LibraryModel) {
        self.init(
            video: video,
            isSelected: model.selection == video,
            isCurrent: model.isCurrentWallpaper(video),
            onSelect: { model.selection = video }
        )
    }
}
