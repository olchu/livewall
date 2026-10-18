import AppKit
import SwiftUI

/// The app's settings, in a popover from the toolbar gear (SPEC.md §3.1).
struct SettingsPanel: View {
    let model: LibraryModel

    var body: some View {
        Form {
            Section("Library") {
                LabeledContent("Folder") {
                    Text(model.folderDisplayPath ?? "Not chosen")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack {
                    Button("Choose Folder…") {
                        model.isShowingSettings = false
                        model.chooseFolder()
                    }
                    if let folder = model.folderURL {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                    }
                }
            }

            Section {
                LabeledContent("Current video") {
                    Text(model.currentWallpaperURL?.lastPathComponent ?? "None")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack {
                    if let current = model.currentWallpaperURL {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([current]) }
                    }
                    Button("Open Wallpaper Settings", action: model.openWallpaperSettings)
                }
            } header: {
                Text("Wallpaper")
            } footer: {
                Text("Pick “LiveWall” once in System Settings → Wallpaper. macOS then plays the video on the desktop and Lock Screen, even with this app closed.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Install Screen Saver…", action: model.installScreenSaver)
            } header: {
                Text("Screen Saver")
            } footer: {
                Text("The legacy screen saver plays the same video.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
