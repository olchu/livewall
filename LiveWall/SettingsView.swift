import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settingsStore = SettingsStore.shared
    private let loginItemManager = LoginItemManager.shared

    var body: some View {
        Form {
            Section("Wallpaper") {
                Picker("Display Mode", selection: playbackMode) {
                    ForEach(PlaybackMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if let url = settingsStore.settings.wallpaperURL {
                    LabeledContent("Current Video", value: url.lastPathComponent)
                } else {
                    LabeledContent("Current Video", value: "None selected")
                }
            }

            Section("Playback") {
                Toggle("Pause on Battery", isOn: boolBinding(\.pauseOnBattery))
                Toggle("Pause on Fullscreen App", isOn: boolBinding(\.pauseWhenFullscreen))
                Toggle("Pause on Screen Lock", isOn: boolBinding(\.pauseWhenLocked))
            }

            Section("System") {
                Toggle("Start at Login", isOn: startAtLogin)
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

    private var playbackMode: Binding<PlaybackMode> {
        Binding {
            settingsStore.settings.playbackMode
        } set: { newValue in
            settingsStore.settings.playbackMode = newValue
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

    private func boolBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding {
            settingsStore.settings[keyPath: keyPath]
        } set: { newValue in
            settingsStore.settings[keyPath: keyPath] = newValue
        }
    }

    private func presentLoginItemError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Could not update Start at Login"
        alert.informativeText = error.localizedDescription
        alert.runModal()
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

private extension PlaybackMode {
    var title: String {
        switch self {
        case .fill: "Fill"
        case .fit: "Fit"
        case .center: "Center"
        }
    }
}
