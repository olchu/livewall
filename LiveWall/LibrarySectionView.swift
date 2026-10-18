import SwiftUI

/// A titled horizontal carousel of cards with ‹ › paging (SPEC.md §3.1).
struct LibrarySectionView: View {
    static let horizontalMargin: CGFloat = 40
    private static let cardSpacing: CGFloat = 24

    let section: LibrarySection
    let model: LibraryModel

    @State private var position = ScrollPosition(idType: URL.self)
    /// Cards at least mostly on screen, in display order — drives paging and
    /// dims the arrows at either end.
    @State private var visibleIDs: [URL] = []

    private var videoIDs: [URL] { section.videos.map(\.id) }
    private var visibleIndices: [Int] { visibleIDs.compactMap { videoIDs.firstIndex(of: $0) }.sorted() }
    private var canPageBack: Bool { (visibleIndices.first ?? 0) > 0 }
    private var canPageForward: Bool { (visibleIndices.last ?? videoIDs.count - 1) < videoIDs.count - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
                .padding(.horizontal, Self.horizontalMargin)

            ScrollView(.horizontal) {
                LazyHStack(spacing: Self.cardSpacing) {
                    ForEach(section.videos) { video in
                        VideoCard(
                            video: video,
                            isSelected: model.selection == video,
                            isCurrent: model.isCurrentWallpaper(video),
                            onSelect: { model.selection = video }
                        )
                        .containerRelativeFrame(.horizontal) { length, _ in
                            // ~3 cards per screen with the next one peeking in.
                            max(260, (length - 2 * Self.cardSpacing) / 3.15)
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 14) // room for the hover lift and shadow
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, Self.horizontalMargin, for: .scrollContent)
            .scrollPosition($position, anchor: .leading)
            .onScrollTargetVisibilityChange(idType: URL.self, threshold: 0.9) { visibleIDs = $0 }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(section.title)
                    .font(.system(size: 26, weight: .bold))
                Text(section.videos.count == 1 ? "1 video" : "\(section.videos.count) videos")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 18) {
                pageButton("chevron.left", label: "Previous", enabled: canPageBack) { page(by: -1) }
                pageButton("chevron.right", label: "Next", enabled: canPageForward) { page(by: 1) }
            }
        }
    }

    private func pageButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? .primary : .tertiary)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    /// Scroll one screenful: forward puts the first card past the visible ones
    /// at the leading edge; back puts the card a screenful earlier there.
    private func page(by direction: Int) {
        let visible = visibleIndices
        guard let first = visible.first, let last = visible.last else { return }
        let target = direction > 0
            ? min(last + 1, videoIDs.count - 1)
            : max(first - visible.count, 0)
        withAnimation(.smooth) { position.scrollTo(id: videoIDs[target], anchor: .leading) }
    }
}
