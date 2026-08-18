import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settingsStore = SettingsStore.shared
    private let loginItemManager = LoginItemManager.shared

    var body: some View {
        Form {
            Section("Wallpaper") {
                if let url = settingsStore.settings.wallpaperURL {
                    LabeledContent("Current Video", value: url.lastPathComponent)
                } else {
                    LabeledContent("Current Video", value: "None selected")
                }
                Text("Played by macOS via the LiveWall wallpaper extension — pick “LiveWall” in System Settings → Wallpaper. This app only selects the video.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("System") {
                Toggle("Start at Login", isOn: startAtLogin)
            }

            Section("Tools") {
                Button("Reveal Optimized Videos") { revealOptimizedVideos() }
                Button("Install Screen Saver…") { installScreenSaver() }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
        .background(SettingsWindowAccessor())
        .onAppear {
            _ = loginItemManager.syncSettingsState(settingsStore)
        }
    }

    private var startAtLogin: Binding<Bool> {
        Binding {
            settingsStore.settings.startAtLogin
        } set: { newValue in
            do {
                try loginItemManager.setEnabled(newValue)
                settingsStore.settings.startAtLogin = loginItemManager.isEnabled
            } catch {
                settingsStore.settings.startAtLogin = loginItemManager.isEnabled
                presentLoginItemError(error)
            }
        }
    }

    private func presentLoginItemError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Could not update Start at Login"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    private func revealOptimizedVideos() {
        guard let dir = try? OptimizedVideoExporter.optimizedWallpapersDirectory() else { return }
        NSWorkspace.shared.open(dir)
    }

    private func installScreenSaver() {
        do {
            try ScreenSaverInstaller.installBundledScreenSaver()
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Could not install LiveWall Screen Saver"
            alert.runModal()
        }
    }

}

private struct SettingsWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                SettingsWindowPresenter.configure(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                SettingsWindowPresenter.configure(window)
            }
        }
    }
}
