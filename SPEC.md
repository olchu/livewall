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

### 3.5 Lock Screen / Screensaver 🔄

macOS restricts app windows to the unlocked user session, so the desktop-level
`WallpaperWindow` cannot appear above the system Lock Screen.

The original implementation assumed that a legacy `.saver` bundle was sufficient on
all supported macOS versions. Testing on macOS 26.5.2 (Tahoe) disproved that assumption:
the bundle installs and builds, but Tahoe's active Lock Screen is driven by the newer
Wallpaper/Aerial provider pipeline. Third-party `.saver` bundles run through
`legacyScreenSaver` and are not a reliable path to animated Lock Screen playback.

#### Current state

| Requirement | Status |
|---|---|
| `.saver` bundle target in Xcode | ✅ `LiveWallScreenSaver` target |
| `ScreenSaverView` subclass playing `AVPlayer` | ✅ `LiveWallScreenSaverView` |
| Video exchange with legacy saver | 🔄 copy to `~/Movies/LiveWall/wallpaper.<ext>` |
| App Group entitlement in both targets | ✅ `group.com.ochurkin.LiveWall` |
| Muted, looping legacy playback | ✅ muted `AVPlayer` + loop observer |
| Reliable Lock Screen animation on macOS 13–15 | ⏳ needs compatibility test matrix |
| Native Wallpaper/Aerial integration on macOS 26+ | ⏳ research and prototype |
| Installed/selected/active status reporting | ⏳ |

App Group ID: `group.com.ochurkin.LiveWall`

#### Target architecture

Lock Screen integration is isolated behind a platform adapter. The rest of the app
must not know whether macOS uses a legacy screen saver or a native wallpaper provider.

```swift
protocol LockScreenWallpaperProviding {
    func prepare(videoURL: URL) async throws
    func activationStatus() async -> LockScreenActivationStatus
    func activate() async throws
    func removeManagedAssets() async throws
}
```

Implementations:

- `LegacyScreenSaverProvider` — macOS 13–15; installs/updates the `.saver`, publishes
  a readable video copy, and directs the user to select LiveWall in System Settings.
- `TahoeWallpaperProvider` — macOS 26+; supplies the selected video to Tahoe's native
  Wallpaper/Aerial pipeline if a supportable and reversible integration is confirmed.
- `UnsupportedLockScreenProvider` — explicit fallback when native activation is not
  safe or available; preserves desktop playback and explains the limitation.

Provider selection is based on `ProcessInfo.operatingSystemVersion`. Dependency
injection is used so status detection and activation can be unit tested without
changing the user's wallpaper configuration.

#### Tahoe implementation plan

**Phase 1 — Baseline and evidence**

- Record behavior on macOS 13, 14, 15, and 26 for preview, idle start, Apple menu
  `Lock Screen`, sleep/wake, logout, multiple displays, and multiple Spaces.
- Confirm the selected Idle provider from
  `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`.
- Capture `legacyScreenSaver`, `WallpaperAgent`, and LiveWall logs so installation,
  selection, loading, decoding, and Lock Screen presentation are distinguishable.
- Add a small diagnostic report to Settings; it must redact user paths before export.

**Phase 2 — Native Tahoe feasibility spike**

- Determine whether macOS 26 exposes a public or supported provider/asset registration
  mechanism for third-party video wallpaper.
- Prototype with one app-owned H.264/HEVC `.mov`, thumbnail, stable identifier, and
  no modification of Apple-downloaded assets.
- Verify that macOS, not the LiveWall process, renders the prototype during idle and
  on the Lock Screen with the system clock visible.
- Verify behavior after LiveWall quits, reboot, sleep/wake, display changes, and video
  replacement.
- Document every filesystem/configuration change made by the prototype.

**Go/no-go gate:** ship `TahoeWallpaperProvider` only if activation is deterministic,
survives reboot, can be fully reversed, does not replace Apple assets, and does not
require disabling SIP or weakening system security. Direct writes to undocumented
Wallpaper databases/manifests remain experimental until these conditions are met.

**Phase 3 — Production provider**

- Copy/transcode the selected source into an app-owned managed-assets directory using
  an atomic temporary-file replacement.
- Generate the still frame/thumbnail required by System Settings.
- Register a stable LiveWall asset/provider entry without touching unrelated choices.
- Activate it for `Idle` while preserving the user's previous Idle selection for
  rollback.
- Make repeated activation idempotent and clean up obsolete managed videos.
- Restore the previous selection and remove only LiveWall-owned assets on disable or
  uninstall.

**Phase 4 — UX**

- Replace `Install Screen Saver…` with a version-aware `Lock Screen` settings section.
- Show one of: `Not configured`, `Preparing`, `Select in System Settings`, `Active`,
  `Needs repair`, or `Unsupported on this macOS version`.
- Provide `Use Current Video on Lock Screen`, `Open Wallpaper Settings`, `Repair`,
  and `Disable & Restore Previous` actions as appropriate.
- Never report success merely because a `.saver` bundle was copied; success requires
  the system's active Idle provider to resolve to LiveWall.

**Phase 5 — Verification**

- Unit-test provider selection, state transitions, idempotency, rollback metadata,
  managed-path validation, and failure recovery.
- Integration-test supported codecs, corrupt/removed files, rapid video changes,
  FileVault lock, manual lock, idle lock, sleep/wake, reboot, and multiple displays.
- Measure Lock Screen startup latency, CPU/GPU use, and disk growth.
- Sign and notarize the app plus every executable bundle; verify both `arm64` and
  `x86_64` for the legacy `.saver`.

#### Expected user flow

1. User selects a video in LiveWall.
2. LiveWall prepares a platform-appropriate Lock Screen asset.
3. User confirms activation or completes the required choice in System Settings.
4. LiveWall verifies the active Idle provider and shows `Active`.
5. macOS renders the video during screen saver/Lock Screen; LiveWall's desktop window
   remains paused while the session is locked.

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
├── LockScreenWallpaperProvider  🔄 platform adapter
│   ├── LegacyScreenSaverProvider ⏳ macOS 13–15
│   ├── TahoeWallpaperProvider    ⏳ macOS 26+ feasibility spike
│   └── UnsupportedProvider       ⏳ safe fallback
│
└── LiveWallScreenSaver           🔄 legacy compatibility path
    ├── .saver bundle target      ✅ LiveWallScreenSaver
    ├── ScreenSaverView subclass  ✅ LiveWallScreenSaverView
    ├── AVPlayer (muted, looping) ✅
    └── reads managed copy from ~/Movies/LiveWall 🔄
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
| **v0.5** | legacy `.saver` prototype; proved insufficient as the Tahoe primary path | 🔄 |
| **v0.6** | crossfade loop transition — dual-player smooth mix with configurable duration | ✅ Done |
| **v0.7** | Lock Screen provider abstraction, OS compatibility matrix, Tahoe feasibility spike | ⏳ |
| **v0.8** | production Tahoe provider, activation UX, rollback, integration tests | ⏳ |
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
| Legacy `.saver` unreliable on Tahoe | Keep it as a compatibility path; use a versioned provider abstraction |
| Tahoe native pipeline is not clearly documented | Feasibility spike + go/no-go gate before production implementation |
| Wallpaper configuration corruption | No broad replacement; atomic writes, backup exact prior state, scoped rollback |
| App update/uninstall leaves managed assets | Stable ownership metadata + remove only LiveWall-owned files |

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
