# LiveWall Lite — Technical Specification

> Living document. Status markers: ✅ Implemented · 🔄 Partial · ⏳ Planned · ❌ Out of scope

---

## 1. Product Overview

**Product Name:** LiveWall Lite  
**Goal:** Lightweight macOS utility for animated desktop wallpapers using local video files.

Primary objectives:
- minimal CPU/GPU usage
- minimal RAM usage
- minimal disk footprint
- native macOS experience — no Electron, no unnecessary background services

---

## 2. Platform

| Setting | Value |
|---|---|
| OS | macOS 13 Ventura+ |
| Language | Swift |
| UI | SwiftUI + AppKit |
| Video Engine | AVFoundation |
| App Type | Menu Bar Utility |
| Architecture | Apple Silicon first |

---

## 3. Core Features

### 3.1 Menu Bar Application ✅

```
LiveWall Lite
────────────────
[Preview thumbnail]          ✅ video first frame, 280×100, rounded top corners
  [Select Wallpaper… button] ✅ ghost button centered on preview, opens file picker
────────────────
Pause / Resume              ✅
────────────────
Pause on Battery            ✅ PlaybackCoordinator + PowerModeMonitor
Pause on Fullscreen App     ✅ PlaybackCoordinator + FullscreenAppMonitor
Pause on Screen Lock        ✅ PlaybackCoordinator + DistributedNotificationCenter
────────────────
Start at Login: On/Off      ✅ `LoginItemManager` + `SMAppService`
Settings...                 ✅ SwiftUI Settings scene (⌘,)
Quit                        ✅
────────────────
CPU:  3.2%                  ✅ PerformanceMonitor
RAM:  87 MB                 ✅ PerformanceMonitor
GPU:  ~45 MB (device)       ✅ PerformanceMonitor
```

Performance metrics notes:
- CPU — per-process, via `mach` `task_threads` + `thread_basic_info`
- RAM — per-process physical footprint, via `task_vm_info` (`phys_footprint`)
- GPU — `MTLDevice.currentAllocatedSize` (device-wide, not per-process; sandbox limitation)
- Metrics update only when menu is open (`NSMenuDelegate`) — no background polling
- Fullscreen detection requires Screen Recording permission (macOS 10.15+); gracefully disabled without it

Requirements:
- ✅ no Dock icon (`LSUIElement = YES` + `.accessory` activation policy)
- ✅ no Cmd+Tab appearance
- ✅ lightweight background behavior

---

### 3.2 Wallpaper Source ✅

Supported formats:
- ✅ `.mp4`
- ✅ `.mov`
- ✅ `.m4v`

Recommended encoding: H.264 or H.265 / 24–30 FPS / 1080p–1440p / no audio.  
GIF: ❌ not used.

Optional optimizer:
- ✅ user can create an optimized local copy when selecting a wallpaper
- ✅ optimized files are stored under Application Support / LiveWall / OptimizedWallpapers
- ✅ original user video is never modified
- ✅ optimizer prefers built-in AVFoundation 1080p export for lower decode cost
- ✅ success notification confirms the optimized file
- ✅ failed optimization falls back to the original video and shows an alert
- 🔄 future: explicit FPS / bitrate controls via AVAssetReader + AVAssetWriter if needed

---

### 3.3 Wallpaper Rendering ✅

| Requirement | Status |
|---|---|
| borderless fullscreen-sized window | ✅ `NSWindow.makeWallpaperWindow(screen:)` factory |
| below desktop icons | ✅ `CGWindowLevelForKey(.desktopWindow)` |
| ignores mouse events | ✅ |
| not focusable / non-activating | ✅ |
| stays behind Finder | ✅ |
| survive sleep/wake | ✅ `SystemEventMonitor` → `PlaybackCoordinator.handleWake()` |
| multiple monitors | ✅ `WallpaperWindowManager` iterates `NSScreen.screens` |
| menu bar contrast sync | ✅ first video frame saved as desktop picture via `DesktopWallpaperSync` |

macOS chooses menu bar text color and top-bar material from the system desktop picture,
not from the custom desktop-level video window. When a video wallpaper is selected or
restored, LiveWall extracts a still frame and sets it as the real desktop picture first,
then renders the animated wallpaper above it. Preview images are written to unique
Application Support URLs so macOS refreshes cached desktop / lock-screen imagery
when a different video is selected.

---

### 3.5 Lock Screen / Screensaver ⏳ v0.5

macOS restricts app windows to the user session — they are always behind the lock screen UI.
To show animated wallpaper during lock, a `ScreenSaver` extension (`.saver` bundle) is required.

| Requirement | Status |
|---|---|
| `.saver` bundle target in Xcode | ✅ `LiveWallScreenSaver` target |
| `ScreenSaverView` subclass playing `AVPlayer` | ✅ `LiveWallScreenSaverView` |
| Shared `UserDefaults` via App Group to read `wallpaperURL` | ✅ shared security-scoped bookmark + path fallback |
| App Group entitlement in both targets | ✅ `group.com.ochurkin.LiveWall` |
| Muted, looping playback matching main app behavior | ✅ muted `AVPlayer` + loop observer |

App Group ID: `group.com.ochurkin.LiveWall`

User flow: user sets LiveWall as their system screensaver in System Settings → Screen Saver.
The same video plays during idle/screensaver and on the lock screen.

---

### 3.4 Video Playback ✅

| Requirement | Status |
|---|---|
| infinite loop | ✅ `AVQueuePlayer` + `AVPlayerLooper` |
| hardware accelerated decoding | ✅ `AVPlayerLayer` |
| muted | ✅ `player.isMuted = true` |
| pause/resume | ✅ |
| display modes: Fill / Fit / Center | ✅ Settings UI updates `AVPlayerLayer.videoGravity` |
| crossfade loop transition (smooth mix) | ✅ `VideoWallpaperView` dual-player mode |
| crossfade duration: 0.5–5.0 s, clamped to ≤ 50% of video duration | ✅ Settings UI slider |
| video duration detection (guard: transition safe) | ✅ `AVURLAsset.load(.duration)` async |

**Crossfade implementation (v0.6):**  
When enabled, `VideoWallpaperView` switches to dual-player mode instead of `AVPlayerLooper`.  
Two `AVPlayer` + two `AVPlayerLayer` (layerA opacity=1, layerB opacity=0) play the same URL.  
A boundary time observer on the active player fires at `currentDuration − crossfadeDuration`.  
At that point: standby player seeks to 0 and plays; `CATransaction` animates opacity swap over `crossfadeDuration` seconds.  
After transition completes: old active player pauses and seeks to 0; roles swap; new boundary observer is registered on the now-active player.

---

## 4. Settings

### 4.1 AppSettings ✅

| Field | Type | Status |
|---|---|---|
| `wallpaperURL` | `URL?` | ✅ persisted via security-scoped bookmark |
| `playbackMode` | `PlaybackMode` | ✅ |
| `startAtLogin` | `Bool` | ✅ `LoginItemManager` + `SMAppService` |
| `batterySaverEnabled` | `Bool` | ✅ toggled via menu |
| `pauseOnBattery` | `Bool` | ✅ `PowerModeMonitor` + `PlaybackCoordinator` |
| `pauseWhenFullscreen` | `Bool` | ✅ `FullscreenAppMonitor` + `PlaybackCoordinator` |
| `pauseWhenLocked` | `Bool` | ✅ `DistributedNotificationCenter` + `PlaybackCoordinator` |
| `crossfadeEnabled` | `Bool` (default `false`) | ✅ |
| `crossfadeDuration` | `Double` seconds (default `1.5`, range `0.5–5.0`) | ✅ |

Persistence: ✅ `UserDefaults` via `SettingsStore`

---

## 5. Performance Requirements

### 5.1 Goals

| Metric | Target | Status |
|---|---|---|
| RAM | 80–120 MB | ⏳ to measure |
| CPU at 1080p | 3–8% | ⏳ to measure |
| CPU paused | ~0% | ✅ `AVPlayer.pause()` |
| App size | < 50 MB | ⏳ to measure |

### 5.2 Forbidden Technologies ✅
Electron, WebView, GIF, HTML/CSS wallpapers, polling loops, 4K unoptimized, 60 FPS default — all excluded.

### 5.3 Required Optimizations

| Optimization | Status |
|---|---|
| `AVPlayerLayer` | ✅ |
| Hardware video decoding | ✅ |
| Lazy loading | ✅ load only when URL provided |
| Pause during sleep | ✅ `SystemEventMonitor` → `PlaybackCoordinator` |
| Pause during lock screen | ✅ `PlaybackCoordinator` + `com.apple.screenIsLocked` |
| Pause on fullscreen app | ✅ `FullscreenAppMonitor` (requires Screen Recording permission) |
| Battery-aware behavior | ✅ `PowerModeMonitor` (IOKit, no polling) |
| `CATransaction.disableActions` on resize | ✅ `VideoWallpaperView.layout()` |
| `drawsAsynchronously` on playerLayer | ✅ |
| Optimized local video copy | ✅ `OptimizedVideoExporter` via AVFoundation export presets |

---

## 6. System Event Handling

| Event | Status |
|---|---|
| system sleep / wake | ✅ `SystemEventMonitor` → `PlaybackCoordinator.handleSleep/Wake` |
| screen sleep / wake | ✅ `SystemEventMonitor` → `PlaybackCoordinator.handleScreenSleep/Wake` |
| screen lock / unlock | ✅ `PlaybackCoordinator` via `com.apple.screenIsLocked` distributed notification |
| monitor connected / disconnected | ✅ `didChangeScreenParametersNotification` |
| display layout changes | ✅ `handleDisplayChange()` |
| fullscreen app open / close | ✅ `FullscreenAppMonitor` (NSWorkspace + CGWindowList) |
| power adapter changes | ✅ `PowerModeMonitor` (IOPSNotificationCreateRunLoopSource) |

---

## 7. Architecture ✅

```
LiveWallLiteApp                   ✅ LiveWallApp.swift
│
├── AppDelegate                   ✅ AppDelegate.swift
│   ├── lifecycle
│   ├── notifications
│   └── startup logic
│
├── MenuBarController             ✅ MenuBarController.swift
│   ├── NSStatusItem
│   └── menu actions + toggles
│
├── PlaybackCoordinator           ✅ PlaybackCoordinator.swift
│   ├── aggregates all pause conditions
│   ├── user pause / battery / fullscreen / lock / sleep
│   └── single source of truth for playback state
│
├── WallpaperWindowManager        ✅ WallpaperWindowManager.swift
│   ├── create windows
│   ├── destroy windows
│   ├── reload wallpapers
│   └── monitor changes
│
├── WallpaperWindow               ✅ WallpaperWindow.swift
│   └── NSWindow factory extension (macOS 26 compat)
│
├── VideoWallpaperView            ✅ VideoWallpaperView.swift
│   ├── looper mode: AVQueuePlayer + AVPlayerLooper (default)
│   ├── crossfade mode: dual AVPlayer + dual AVPlayerLayer (v0.6)
│   ├── boundary time observer → opacity swap via CATransaction
│   └── setCrossfade(enabled:duration:) reloads into correct mode
│
├── DesktopWallpaperSync          ✅ DesktopWallpaperSync.swift
│   ├── extracts preview frame with AVAssetImageGenerator
│   ├── stores unique cached JPG previews in Application Support
│   └── sets NSWorkspace desktop picture for menu bar contrast
│
├── OptimizedVideoExporter        ✅ OptimizedVideoExporter.swift
│   ├── creates lower-cost playback copies via AVAssetExportSession
│   ├── stores files in Application Support / OptimizedWallpapers
│   └── leaves source video unchanged
│
├── PerformanceMonitor            ✅ PerformanceMonitor.swift
│   ├── CPU (per-process, mach task_threads)
│   ├── RAM (phys_footprint)
│   └── GPU (MTLDevice.currentAllocatedSize)
│
├── SettingsStore                 ✅ SettingsStore.swift
│   └── UserDefaults + security-scoped bookmarks
│
├── SystemEventMonitor            ✅ SystemEventMonitor.swift
│   └── sleep/wake → PlaybackCoordinator
│
├── PowerModeMonitor              ✅ PowerModeMonitor.swift
│   └── IOKit battery state, no polling
│
├── FullscreenAppMonitor          ✅ FullscreenAppMonitor.swift
│   └── NSWorkspace + CGWindowList
│
├── LoginItemManager              ✅ LoginItemManager.swift
│   └── launch at login
│
└── LiveWallScreenSaver           ⏳ v0.5
    ├── .saver bundle target      ✅ LiveWallScreenSaver
    ├── ScreenSaverView subclass  ✅ LiveWallScreenSaverView
    ├── AVPlayer (muted, looping) ✅
    └── reads wallpaperURL via App Group UserDefaults ✅
```

---

## 8. Component Contracts

### 8.1 WallpaperWindowManaging ✅
```swift
protocol WallpaperWindowManaging {
    func setupWallpaperWindows()
    func destroyWallpaperWindows()
    func reloadWallpaper()
    func pause()
    func resume()
    func handleDisplayChange()
}
```

### 8.2 VideoPlayback ✅
```swift
protocol VideoPlayback {
    func loadVideo(url: URL)
    func play()
    func pause()
    func setGravity(_ mode: PlaybackMode)
}
```

### 8.3 AppSettings ✅
```swift
struct AppSettings: Codable {
    var wallpaperURL: URL?         // resolved from security-scoped bookmark via SettingsStore
    var playbackMode: PlaybackMode
    var startAtLogin: Bool
    var batterySaverEnabled: Bool
    var pauseOnBattery: Bool
    var pauseWhenFullscreen: Bool
    var pauseWhenLocked: Bool
}
```

---

## 9. UX — First Launch ⏳ v0.4

```
1. App launches in menu bar
2. Settings are available from menu        ← v0.4
3. User selects video wallpaper
4. Wallpaper starts immediately
```

Current behaviour (v0.3): app launches silently in menu bar, restores last wallpaper automatically, user selects video via menu. Pause conditions (battery/fullscreen/lock) configurable via menu toggles.

---

## 10. Development Roadmap

| Version | Scope | Status |
|---|---|---|
| **v0.1** | menu bar, MP4, rendering, loop, pause/resume, quit | ✅ Done |
| **v0.2** | multi-monitor, sleep/wake recovery, display changes, persistence | ✅ Done |
| **v0.3** | battery saver, pause on battery/fullscreen/lock, performance metrics | ✅ Done |
| **v0.4** | settings window, playback modes UI, launch at login | ✅ Done |
| **v0.5** | screensaver extension — animated wallpaper on lock screen | ⏳ |
| **v0.6** | crossfade loop transition — dual-player smooth mix with configurable duration | ✅ Done |
| **v1.0** | signed, notarized, DMG, optimized | ⏳ |

---

## 11. Out of Scope ❌

online marketplace · accounts · cloud sync · AI generation · video editor ·
audio wallpapers · Windows support · web wallpapers · animated HTML

---

## 12. Technical Risks

| Risk | Mitigation |
|---|---|
| Desktop window layering | `CGWindowLevelForKey(.desktopWindow)` + factory pattern (macOS 26 compat) |
| Mission Control / Spaces | `.canJoinAllSpaces` + `.stationary` collection behavior |
| Sleep/wake edge cases | `SystemEventMonitor` → `PlaybackCoordinator` + window recreation on wake |
| Multiple monitor sync | per-screen `NSWindow` instances |
| Sandbox file access | ✅ security-scoped bookmarks (`SettingsStore`) + `user-selected.read-write` entitlement |
| Fullscreen detection without SR permission | `FullscreenAppMonitor` returns `false` — no false positives |
| Menu bar contrast mismatch | `DesktopWallpaperSync` sets first video frame as real desktop picture before video overlay |
| Per-Space desktop pictures | Current Space sync is supported; other Spaces may keep their own desktop picture until activated/resynced |

---

## 13. Xcode Project

```
Product Name:          LiveWall
Bundle Identifier:     com.ochurkin.LiveWall
Interface:             SwiftUI
Language:              Swift
Min Deployment:        macOS 13
LSUIElement:           YES
Sandbox:               YES
Entitlements:          LiveWall/LiveWall.entitlements
  com.apple.security.app-sandbox: YES
  com.apple.security.files.user-selected.read-write: YES
```

Distribution:
- ✅ DMG installer: `scripts/build_dmg.sh`
- ✅ default local signing: ad-hoc `CODE_SIGN_IDENTITY=-` with app entitlements
- ⏳ public distribution: Developer ID signing + notarization

---

## 14. Future Ideas (Post v1.0)

wallpaper playlists · dynamic by time of day · online packs ·
performance presets · GPU monitor · live shader wallpapers · transcoding optimizer
