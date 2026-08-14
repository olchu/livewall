import AppKit
import AVFoundation
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settingsStore = SettingsStore.shared
    private let loginItemManager = LoginItemManager.shared
    @State private var videoDuration: Double? = nil
    @State private var isUpdatingLockScreen = false
    @State private var lockScreenMessage: String?

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

            Section("Lock Screen") {
                Button("Use Current Video on Lock Screen") {
                    applyLockScreenWallpaper()
                }
                .disabled(lockScreenSourceURL == nil || isUpdatingLockScreen)

                Button("Restore Original Dubai") {
                    restoreLockScreenWallpaper()
                }
                .disabled(!LockScreenWallpaperManager.canRestore || isUpdatingLockScreen)

                if isUpdatingLockScreen {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Preparing a macOS-compatible Lock Screen video…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let lockScreenMessage {
                    Text(lockScreenMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Requires macOS 26 and the Dubai wallpaper downloaded in System Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

    private var lockScreenSourceURL: URL? {
        if let wallpaperURL = settingsStore.settings.wallpaperURL {
            return wallpaperURL
        }

        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies/LiveWall", isDirectory: true)
        return ["mp4", "mov", "m4v"]
            .map { directory.appendingPathComponent("wallpaper.\($0)") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
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

    private func applyLockScreenWallpaper() {
        guard let videoURL = lockScreenSourceURL else { return }
        isUpdatingLockScreen = true
        lockScreenMessage = nil

        Task {
            do {
                try await LockScreenWallpaperManager.apply(videoURL: videoURL)
                lockScreenMessage = "Applied and activated. Lock the Mac to verify the animated wallpaper."
            } catch {
                presentLockScreenError(error)
            }
            isUpdatingLockScreen = false
        }
    }

    private func restoreLockScreenWallpaper() {
        isUpdatingLockScreen = true
        lockScreenMessage = nil

        do {
            try LockScreenWallpaperManager.restore()
            lockScreenMessage = "The original Dubai wallpaper was restored."
        } catch {
            presentLockScreenError(error)
        }
        isUpdatingLockScreen = false
    }

    private func presentLockScreenError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Could not update Lock Screen wallpaper"
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
