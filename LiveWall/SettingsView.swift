import AppKit
import AVFoundation
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settingsStore = SettingsStore.shared
    private let loginItemManager = LoginItemManager.shared
    @State private var videoDuration: Double? = nil

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

            Section("Loop Transition") {
                Toggle("Smooth Crossfade", isOn: boolBinding(\.crossfadeEnabled))

                if settingsStore.settings.crossfadeEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Duration")
                            Spacer()
                            Text(String(format: "%.1f s", settingsStore.settings.crossfadeDuration))
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: crossfadeDurationBinding,
                            in: 0.5...maxCrossfadeDuration,
                            step: 0.5
                        )
                        if let dur = videoDuration {
                            let safe = settingsStore.settings.crossfadeDuration < dur * 0.5
                            Text(safe
                                 ? "Video length: \(Int(dur)) s"
                                 : "Duration exceeds 50% of video length (\(Int(dur)) s) — crossfade disabled")
                                .font(.caption)
                                .foregroundStyle(safe ? Color.secondary : Color.red)
                        }
                    }
                }
            }
            .task(id: settingsStore.settings.wallpaperURL) {
                videoDuration = await detectVideoDuration(url: settingsStore.settings.wallpaperURL)
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

    private var maxCrossfadeDuration: Double {
        if let dur = videoDuration { return min(5.0, dur * 0.5) }
        return 5.0
    }

    private var crossfadeDurationBinding: Binding<Double> {
        Binding {
            settingsStore.settings.crossfadeDuration
        } set: { newValue in
            settingsStore.settings.crossfadeDuration = newValue
        }
    }

    private func detectVideoDuration(url: URL?) async -> Double? {
        guard let url else { return nil }
        let asset = AVURLAsset(url: url)
        return try? await asset.load(.duration).seconds
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

private extension PlaybackMode {
    var title: String {
        switch self {
        case .fill: "Fill"
        case .fit: "Fit"
        case .center: "Center"
        }
    }
}
