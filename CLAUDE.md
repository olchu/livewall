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
├── LiveWall/                      ← main app: pure configurator, renders nothing (flat, no subdirectories)
│   ├── LiveWallApp.swift           entry point, @main, AppDelegate adaptor
│   ├── AppDelegate.swift           app lifecycle — starts the menu bar only, no rendering
│   ├── MenuBarController.swift     NSStatusItem, menu: Select Wallpaper / Settings / Quit
│   ├── SettingsView.swift          SwiftUI Settings window
│   ├── SettingsWindowPresenter.swift
│   ├── SettingsStore.swift         UserDefaults + security-scoped bookmarks; posts a Darwin
│   │                               notification on wallpaper change so the extension hot-reloads
│   ├── AppSettings.swift           Codable settings struct
│   ├── PerformanceMonitor.swift    CPU (mach task_threads), RAM (phys_footprint), GPU (MTLDevice)
│   ├── OptimizedVideoExporter.swift  optional 1080p/HEVC re-encode of a picked video
│   ├── LoginItemManager.swift      launch at login (SMAppService)
│   └── ScreenSaverInstaller.swift  installs the legacy .saver bundle (macOS 13–15 fallback)
└── LiveWallWallpaperExtension/     ← com.apple.wallpaper ExtensionKit extension — owns ALL rendering
    ├── LiveWallWallpaperExtension.swift  entry point; starts PlaybackPolicy + VideoSourceWatcher
    ├── WallpaperExtensionConfig.swift    accepts XPC from WallpaperAgent
    ├── WallpaperXPCHandler.swift         acquire/update/invalidate/snapshot/settings
    ├── WallpaperState.swift              per-surface CAContext registry, keyed by WallpaperID UUID
    ├── VideoRenderer.swift               AVSampleBufferDisplayLayer + manual AVAssetReader
    ├── VideoSource.swift                 reads ~/Movies/LiveWall/wallpaper.<ext>
    ├── VideoSourceWatcher.swift          Darwin notification → hot-swaps renderers on wallpaper change
    ├── PlaybackPolicy.swift              thermal-state pause/resume (Phase 4)
    └── ...                               CallerValidation, Logging, RuntimeHelpers, etc.
```

**The app never plays video itself.** `LiveWall.app` only lets the user pick a video, copies it to
`~/Movies/LiveWall/wallpaper.<ext>`, and signals the extension. Playback — desktop AND Lock Screen —
is rendered entirely by `WallpaperAgent` hosting `LiveWallWallpaperExtension`, and keeps running with
`LiveWall.app` fully quit. See SPEC.md §3.5. Do not reintroduce app-side rendering (an `NSWindow`
overlay, `AVPlayerLayer`, etc.) — this was the pre-v0.7 architecture and was deliberately retired.

**File system sync:** The Xcode project uses `PBXFileSystemSynchronizedRootGroup` — any `.swift` file added to `LiveWall/` or `LiveWallWallpaperExtension/` is automatically included in that folder's target. No need to modify `project.pbxproj` manually.

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
| Rendering owner | `LiveWallWallpaperExtension` only — the app never renders; see SPEC.md §3.5 |
| Settings persistence | `SettingsStore.shared` — always use `setWallpaperURL(_:)` to pick a file (not direct assignment), security-scoped bookmark handles sandbox, posts the extension's reload notification |
| No Dock icon | `LSUIElement=YES` in build settings + `NSApp.setActivationPolicy(.accessory)` |
| Sandbox | `ENABLE_APP_SANDBOX = YES` on both targets — file access requires security-scoped bookmarks / temporary-exception entitlements |
| Extension window level | `CAContext` hosted by `WallpaperAgent` via ExtensionKit — not an app-owned `NSWindow` |
| Loop playback | `VideoRenderer` — fresh `AVAssetReader` per loop, PTS/DTS offset kept monotonic |
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
| v0.3 Optimization | ✅ Done |
| v0.4 Settings UI | ✅ Done |
| v0.5 Legacy `.saver` prototype | 🔄 |
| v0.6 Crossfade loop transition | ✅ Done |
| v0.7 Wallpaper ExtensionKit skeleton (§3.5 Phase 1) | 🔄 |
| v0.8 Wallpaper extension: XPC/rendering/resilience (§3.5 Phases 2–4) | 🔄 |
| v1.0 Production | ⏳ |

Full feature status → see `SPEC.md`.
