import AppKit
import SwiftUI

/// The app's only window (SPEC.md §3.1): the library folder's videos as
/// carousel sections (or one grid), with a bottom bar to apply the selection.
struct LibraryView: View {
    @Bindable var model: LibraryModel

    var body: some View {
        content
            .frame(minWidth: 900, minHeight: 600)
            .background(Self.background)
            .navigationTitle(model.folderURL?.lastPathComponent ?? "LiveWall")
            .navigationSubtitle(model.folderDisplayPath ?? "")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if model.folderURL != nil {
                        Button("Refresh", systemImage: "arrow.clockwise", action: model.rescan)
                            .help("Rescan the folder")
                    }
                    Button("Choose Folder…", systemImage: "folder", action: model.chooseFolder)
                        .help("Choose the folder LiveWall lists videos from")
                    Button("Settings", systemImage: "gearshape") { model.isShowingSettings.toggle() }
                        .help("Settings (⌘,)")
                        .popover(isPresented: $model.isShowingSettings, arrowEdge: .bottom) {
                            SettingsPanel(model: model)
                        }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if model.sections?.isEmpty == false { bottomBar }
            }
            .task { model.rescan() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                model.rescan()
            }
            .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        if let folder = model.folderURL {
            switch model.sections {
            case nil:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case let sections? where sections.isEmpty:
                emptyState(
                    title: "No videos in “\(folder.lastPathComponent)”",
                    message: "Add .mp4, .mov or .m4v files to this folder or its subfolders, or choose another folder.",
                    systemImage: "film.stack"
                )
            case let sections?:
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 44) {
                        if sections.count == 1, let only = sections.first {
                            LibraryGridSection(section: only, model: model)
                        } else {
                            ForEach(sections) { LibraryCarouselSection(section: $0, model: model) }
                        }
                    }
                    .padding(.vertical, 28)
                }
            }
        } else {
            emptyState(
                title: "Choose a folder with videos",
                message: "LiveWall shows every video in it — each subfolder as its own row.",
                systemImage: "folder.badge.plus"
            )
        }
    }

    private func emptyState(title: String, message: String, systemImage: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            Button("Choose Folder…", action: model.chooseFolder)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if let selection = model.selection {
                Text(selection.name)
                    .font(.headline)
                    .lineLimit(1)
                if model.isCurrentWallpaper(selection) {
                    Text("Current wallpaper").foregroundStyle(.secondary)
                }
            } else {
                Text("Select a video").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Wallpaper Settings", action: model.openWallpaperSettings)
                .help("Pick “LiveWall” once in System Settings → Wallpaper")
            Button("Set as Wallpaper", action: model.setSelectionAsWallpaper)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canSetSelectionAsWallpaper)
        }
        .controlSize(.large)
        .padding(.horizontal, LibraryLayout.horizontalMargin)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private static let background = LinearGradient(
        colors: [Color(red: 0.17, green: 0.18, blue: 0.21), Color(red: 0.12, green: 0.13, blue: 0.15)],
        startPoint: .top,
        endPoint: .bottom
    )
}
