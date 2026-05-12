import SwiftUI

@main
struct LiveWallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No windows — app lives entirely in the menu bar
        Settings { EmptyView() }
    }
}
