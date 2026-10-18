import AppKit
import SwiftUI

@main
struct LiveWallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var library = LibraryModel()

    var body: some Scene {
        Window("LiveWall", id: "library") {
            LibraryView(model: library)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Choose Folder…", action: library.chooseFolder)
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { library.isShowingSettings = true }
                    .keyboardShortcut(",")
            }
            CommandGroup(after: .appInfo) {
                Button("Install Screen Saver…", action: library.installScreenSaver)
            }
        }
    }
}
