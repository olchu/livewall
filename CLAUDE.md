# LiveWall — Claude Development Guide

## Skills

Always use the `swift-development` skill for:
- building and running the Xcode project
- running tests
- managing simulators or build settings
- any Swift/Xcode-specific tooling

Invoke it via `/swift-development` or the Skill tool with `subagent_type` when the task involves building, testing, or deploying.

---

## Project Layout

```
LiveWall/                          ← project root
├── CLAUDE.md                      ← this file
├── SPEC.md                        ← living technical specification (source of truth)
├── LiveWall.xcodeproj/
└── LiveWall/                      ← all Swift source files (flat, no subdirectories)
    ├── LiveWallApp.swift           entry point, @main, AppDelegate adaptor
    ├── AppDelegate.swift           app lifecycle, system notifications, startup
    ├── MenuBarController.swift     NSStatusItem, menu: Select / Pause / Quit
    ├── WallpaperWindowManaging.swift  protocol — window manager contract
    ├── VideoPlayback.swift            protocol — video player contract
    ├── WallpaperWindowManager.swift   manages one WallpaperWindow per NSScreen
    ├── WallpaperWindow.swift          borderless NSWindow at desktop level
    ├── VideoWallpaperView.swift       NSView + AVPlayerLayer, seamless loop
    ├── SystemEventMonitor.swift       sleep/wake/screen events via NSWorkspace
    ├── SettingsStore.swift            UserDefaults + security-scoped bookmarks
    ├── AppSettings.swift              Codable settings struct
    └── PlaybackMode.swift             enum: fill / fit / center
```

**File system sync:** The Xcode project uses `PBXFileSystemSynchronizedRootGroup` — any `.swift` file added to `LiveWall/` is automatically included in the build. No need to modify `project.pbxproj` manually.

---

## Build

```bash
# Build (from project root)
xcodebuild -project LiveWall.xcodeproj -scheme LiveWall -destination 'platform=macOS' build

# Check errors only
xcodebuild ... build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

---

## Key Conventions

| Convention | Detail |
|---|---|
| Architecture | SDD — spec first, protocols define contracts, implementations follow |
| Source of truth | `SPEC.md` — update status markers after every feature |
| Protocols | `WallpaperWindowManaging`, `VideoPlayback` — defined in spec §8 |
| Settings persistence | `SettingsStore.shared` — always use `setWallpaperURL(_:)` to pick a file (not direct assignment), security-scoped bookmark handles sandbox |
| No Dock icon | `LSUIElement=YES` in build settings + `NSApp.setActivationPolicy(.accessory)` |
| Sandbox | `ENABLE_APP_SANDBOX = YES` — file access requires security-scoped bookmarks |
| Window level | `CGWindowLevelForKey(.desktopWindow)` — below Finder icons |
| Loop playback | `AVPlayerItemDidPlayToEndTime` observer — seek to zero and play |
| No GIF | AVFoundation + hardware decoding only |

---

## Platform

| Setting | Value |
|---|---|
| Bundle ID | `com.ochurkin.LiveWall` |
| Swift | 5.0 |
| Min macOS | 13 Ventura |
| Sandbox | YES |
| Hardened Runtime | YES |

---

## Roadmap Status

| Version | Status |
|---|---|
| v0.1 Core MVP | ✅ Done |
| v0.2 Stability | ✅ Done |
| v0.3 Optimization | ⏳ Next |
| v0.4 Settings UI | ⏳ |
| v1.0 Production | ⏳ |

Full feature status → see `SPEC.md`.

---

## v0.3 Planned Components

- `PowerModeMonitor` — pause on battery (`IOKit` / `NSWorkspace.didChangeExternalDisplaysNotification`)
- `FullscreenAppMonitor` — pause when a fullscreen app is active (`NSWorkspace.activeSpaceDidChangeNotification` + accessibility)
- Lock screen pause — `com.apple.screenIsLocked` distributed notification
