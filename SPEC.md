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
Select Wallpaper...    ✅
Pause / Resume         ✅
Battery Saver: On/Off  ⏳ v0.3
Start at Login: On/Off ⏳ v0.4
Settings...            ⏳ v0.4
Quit                   ✅
```

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

---

### 3.3 Wallpaper Rendering ✅

| Requirement | Status |
|---|---|
| borderless fullscreen-sized window | ✅ `WallpaperWindow` |
| below desktop icons | ✅ `CGWindowLevelForKey(.desktopWindow)` |
| ignores mouse events | ✅ |
| not focusable / non-activating | ✅ |
| stays behind Finder | ✅ |
| survive sleep/wake | ⏳ v0.2 |
| multiple monitors | ✅ `WallpaperWindowManager` iterates `NSScreen.screens` |

---

### 3.4 Video Playback ✅

| Requirement | Status |
|---|---|
| infinite loop | ✅ `AVPlayerItemDidPlayToEndTime` observer |
| hardware accelerated decoding | ✅ `AVPlayerLayer` |
| muted | ✅ `player.isMuted = true` |
| pause/resume | ✅ |
| display modes: Fill / Fit / Center | 🔄 enum defined, Center maps to Fit pending custom impl |

---

## 4. Settings

### 4.1 AppSettings ✅

| Field | Type | Status |
|---|---|---|
| `wallpaperURL` | `URL?` | ✅ persisted via security-scoped bookmark |
| `playbackMode` | `PlaybackMode` | ✅ |
| `startAtLogin` | `Bool` | ⏳ v0.4 |
| `batterySaverEnabled` | `Bool` | ⏳ v0.3 |
| `pauseOnBattery` | `Bool` | ⏳ v0.3 |
| `pauseWhenFullscreen` | `Bool` | ⏳ v0.3 |
| `pauseWhenLocked` | `Bool` | ⏳ v0.3 |

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
| Pause during sleep | ✅ `SystemEventMonitor` |
| Pause during lock screen | ⏳ v0.3 |
| Pause on fullscreen app | ⏳ v0.3 |
| Battery-aware behavior | ⏳ v0.3 |

---

## 6. System Event Handling

| Event | Status |
|---|---|
| system sleep / wake | ✅ `SystemEventMonitor` |
| screen sleep / wake | ✅ `SystemEventMonitor` |
| screen lock / unlock | ⏳ v0.3 |
| monitor connected / disconnected | ✅ `didChangeScreenParametersNotification` |
| display layout changes | ✅ `handleDisplayChange()` |
| fullscreen app open / close | ⏳ v0.3 |
| power adapter changes | ⏳ v0.3 |

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
│   └── menu actions
│
├── WallpaperWindowManager        ✅ WallpaperWindowManager.swift
│   ├── create windows
│   ├── destroy windows
│   ├── reload wallpapers
│   └── monitor changes
│
├── WallpaperWindow               ✅ WallpaperWindow.swift
│   └── custom NSWindow
│
├── VideoWallpaperView            ✅ VideoWallpaperView.swift
│   ├── AVPlayer
│   ├── AVPlayerLayer
│   └── loop handling
│
├── SettingsStore                 ✅ SettingsStore.swift
│   └── UserDefaults wrapper
│
├── SystemEventMonitor            ✅ SystemEventMonitor.swift
│   ├── sleep/wake
│   └── screen events
│
├── PowerModeMonitor              ⏳ v0.3
│   └── battery state tracking
│
├── FullscreenAppMonitor          ⏳ v0.3
│   └── fullscreen detection
│
└── LoginItemManager              ⏳ v0.4
    └── launch at login
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
2. Welcome window appears        ← v0.4
3. User selects video wallpaper
4. Wallpaper starts immediately
```

Current behaviour (v0.2): app launches silently in menu bar, restores last wallpaper automatically, user selects video via menu.

---

## 10. Development Roadmap

| Version | Scope | Status |
|---|---|---|
| **v0.1** | menu bar, MP4, rendering, loop, pause/resume, quit | ✅ Done |
| **v0.2** | multi-monitor, sleep/wake recovery, display changes, persistence | ✅ Done |
| **v0.3** | battery saver, pause on battery/fullscreen/lock | ⏳ |
| **v0.4** | settings window, playback modes UI, launch at login | ⏳ |
| **v1.0** | signed, notarized, DMG, optimized | ⏳ |

---

## 11. Out of Scope ❌

online marketplace · accounts · cloud sync · AI generation · video editor ·
audio wallpapers · Windows support · web wallpapers · animated HTML

---

## 12. Technical Risks

| Risk | Mitigation |
|---|---|
| Desktop window layering | `CGWindowLevelForKey(.desktopWindow)` + tested v0.1 |
| Mission Control / Spaces | `.canJoinAllSpaces` + `.stationary` collection behavior |
| Sleep/wake edge cases | `NSWorkspace` notifications + window recreation |
| Multiple monitor sync | per-screen `WallpaperWindow` instances |
| Sandbox file access | ✅ security-scoped bookmarks (`SettingsStore`) |

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
```

---

## 14. Future Ideas (Post v1.0)

wallpaper playlists · dynamic by time of day · online packs ·
performance presets · GPU monitor · live shader wallpapers · transcoding optimizer
