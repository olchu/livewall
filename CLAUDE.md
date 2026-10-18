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
├── LiveWall/                      ← main app: configurator with one library window, renders no
│   │                                 wallpaper (flat, no subdirectories)
│   ├── LiveWallApp.swift           entry point, @main, library Window scene + menu commands
│   ├── AppDelegate.swift           quit on last window close, extension registration
│   ├── LibraryView.swift           the window: sections, bottom bar, empty states
│   ├── LibrarySections.swift       section header, carousel row with ‹ › paging, single-section grid
│   ├── SettingsPanel.swift         settings popover (toolbar gear / ⌘,)
│   ├── VideoCard.swift             16:9 card: thumbnail, hover preview, Current badge
│   ├── LoopingVideoView.swift      muted looping hover preview (UI only — not wallpaper rendering)
│   ├── LibraryModel.swift          folder, sections, selection, Set as Wallpaper
│   ├── VideoLibrary.swift          folder scan → sections (subfolder = section)
│   ├── ThumbnailCache.swift        async card thumbnails, NSCache
│   ├── SettingsStore.swift         UserDefaults + security-scoped bookmarks; copies the wallpaper
│   │                               to ~/Movies/LiveWall and posts the extension's reload notification
│   ├── AppSettings.swift           Codable settings struct
│   ├── WallpaperExtensionRegistrar.swift  pluginkit registration of the bundled extension
│   └── ScreenSaverInstaller.swift  installs the legacy .saver bundle
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
`LiveWall.app` fully quit. See SPEC.md §3.5. Do not reintroduce app-side wallpaper rendering (a desktop
`NSWindow` overlay, etc.) — this was the pre-v0.7 architecture and was deliberately retired. The only
video the app plays is the hover preview inside its own library window (`LoopingVideoView`).

**The app is a regular windowed app** (SPEC.md §3.1): it opens straight into the library window and
quits when it closes — no menu bar extra, no login item, no background presence.

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
| Rendering owner | `LiveWallWallpaperExtension` only — the app never renders wallpapers (its only video is the in-window hover preview); see SPEC.md §3.5 |
| Settings persistence | `SettingsStore.shared` — always use `setWallpaperURL(_:)` to pick a file (not direct assignment), security-scoped bookmark handles sandbox, posts the extension's reload notification |
| App type | Regular app with Dock icon, single `Window` scene; quits on last window close |
| Sandbox | Only the extension is sandboxed (`ENABLE_APP_SANDBOX = YES`, read-only temporary exception for `~/Movies/LiveWall/`). The app and `.saver` have `ENABLE_APP_SANDBOX = NO`; `SettingsStore` still keeps security-scoped bookmarks |
| Extension window level | `CAContext` hosted by `WallpaperAgent` via ExtensionKit — not an app-owned `NSWindow` |
| Loop playback | `VideoRenderer` — fresh `AVAssetReader` per loop, PTS/DTS offset kept monotonic |
| No GIF | AVFoundation + hardware decoding only |

---

## Platform

| Setting | Value |
|---|---|
| Bundle ID | `com.ochurkin.LiveWall` |
| Swift | 5.0 |
| Min macOS | 26 (project-level `MACOSX_DEPLOYMENT_TARGET`) |
| Sandbox | extension only |
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
| v0.9 Library window replaces the menu bar app (§3.1) | 🔄 |
| v1.0 Production | ⏳ |

Full feature status → see `SPEC.md`.
