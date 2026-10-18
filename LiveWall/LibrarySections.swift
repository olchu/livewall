import SwiftUI

/// Layout shared by the library's section views (SPEC.md §3.1).
enum LibraryLayout {
    static let horizontalMargin: CGFloat = 40
    static let cardSpacing: CGFloat = 24
}

/// Section title, video count, and an optional trailing accessory.
struct SectionHeader<Accessory: View>: View {
    let section: LibrarySection
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(section.title)
                    .font(.system(size: 26, weight: .bold))
                Text("^[\(section.videos.count) video](inflect: true)")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            accessory
        }
        .padding(.horizontal, LibraryLayout.horizontalMargin)
    }
}

/// The only section, as a wrapping grid — it lives inside the window's
/// vertical scroll view.
struct LibraryGridSection: View {
    private static let columns = [GridItem(.adaptive(minimum: 300, maximum: 520), spacing: LibraryLayout.cardSpacing)]

    let section: LibrarySection
    let model: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(section: section) {}
            LazyVGrid(columns: Self.columns, spacing: 28) {
                ForEach(section.videos) { VideoCard(video: $0, model: model).equatable() }
            }
            .padding(.horizontal, LibraryLayout.horizontalMargin)
            .padding(.vertical, 14) // room for the hover lift and shadow
        }
    }
}

/// One of several sections, as a horizontal carousel with ‹ › paging.
struct LibraryCarouselSection: View {
    let section: LibrarySection
    let model: LibraryModel

    @State private var position = ScrollPosition(idType: URL.self)
    /// Indices of the cards at least mostly on screen — drives paging and dims
    /// the arrows at either end.
    @State private var visibleRange: ClosedRange<Int>?

    private var canPageBack: Bool { (visibleRange?.lowerBound ?? 0) > 0 }
    private var canPageForward: Bool { (visibleRange?.upperBound ?? Int.max) < section.videos.count - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(section: section) {
                HStack(spacing: 18) {
                    pageButton("chevron.left", label: "Previous", enabled: canPageBack) { page(by: -1) }
                    pageButton("chevron.right", label: "Next", enabled: canPageForward) { page(by: 1) }
                }
            }

            ScrollView(.horizontal) {
                LazyHStack(spacing: LibraryLayout.cardSpacing) {
                    ForEach(section.videos) { video in
                        VideoCard(video: video, model: model)
                            .equatable()
                            .containerRelativeFrame(.horizontal) { length, _ in
                                // ~3 cards per screen with the next one peeking in.
                                max(260, (length - 2 * LibraryLayout.cardSpacing) / 3.15)
                            }
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 14) // room for the hover lift and shadow
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, LibraryLayout.horizontalMargin, for: .scrollContent)
            .scrollPosition($position, anchor: .leading)
            .onScrollTargetVisibilityChange(idType: URL.self, threshold: 0.9) { ids in
                let indices = ids.compactMap { id in section.videos.firstIndex { $0.id == id } }
                visibleRange = indices.min().flatMap { low in indices.max().map { low...$0 } }
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
        guard let visible = visibleRange else { return }
        let target = direction > 0
            ? min(visible.upperBound + 1, section.videos.count - 1)
            : max(visible.lowerBound - visible.count, 0)
        withAnimation(.smooth) { position.scrollTo(id: section.videos[target].id, anchor: .leading) }
    }
}
