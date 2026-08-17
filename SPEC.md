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

**Abandoned approach — direct Aerial asset substitution.** A v0.5 attempt
(`LockScreenWallpaperManager`, since removed) overwrote the on-disk video for an
existing Apple Aerial (`~/Library/Application Support/com.apple.wallpaper/aerials/videos/{id}.mov`)
and patched the internal `Store/Index.plist`. This reliably produced a black screen
on wake/lock-cycling and broke Mission Control desktop thumbnails. Root cause,
confirmed two ways: (1) the substituted video didn't match the asset's manifest-declared
specs (`~/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json`
declares this asset as 4K/SDR/**240fps** — unreproducible from arbitrary user video), and
(2) external confirmation from Cindori's *Backdrop* developer (the first app to
reverse-engineer custom Lock Screen video): naively substituting/cycling an Aerial
asset "will eventually crash the wallpaper extension, producing a black screen" even
with correctly-specced video. This is a real bug in Apple's `WallpaperAgent`/Aerial
render pipeline, not something fixable by matching file specs more closely. This path
is closed; do not resume it. `ENABLE_APP_SANDBOX` was restored to `YES` after removal.

**Current approach — `com.apple.wallpaper` ExtensionKit extension.** Modeled on
[Phosphene](https://github.com/kageroumado/phosphene) (MIT), which uses the same
technique to ship custom video wallpapers to both desktop and Lock Screen without
touching any Apple-owned asset. Instead of substituting content into an existing
system-managed asset, LiveWall registers as its **own** wallpaper provider — a
peer of Apple's built-in Aerials in System Settings → Wallpaper — via the
`com.apple.wallpaper` ExtensionKit extension point (introduced macOS 14) and the
private `WallpaperExtensionKit.framework` (loaded via `dlopen`, since it ships no
public headers). This is still Apple's own render pipeline underneath, so the
`WallpaperAgent` instability above is not fully avoidable — Phosphene handles it
with an explicit "spiral of death" detector that auto-restarts the agent — but the
failure mode is *system-wide flakiness to defend against*, not something LiveWall's
own hack directly causes by corrupting a signed asset out from under macOS.

#### Current state

| Requirement | Status |
|---|---|
| `LiveWallWallpaperExtension.appex` target (ExtensionKit) | ✅ `com.apple.product-type.extensionkit-extension`, embeds via `$(EXTENSIONS_FOLDER_PATH)` |
| `Info.plist` declares `com.apple.wallpaper` extension point | ✅ `EXAppExtensionAttributes.EXExtensionPointIdentifier` |
| Extension sandboxed, builds Debug + Release | ✅ |
| `dlopen` of `WallpaperExtensionKit.framework` + read-only class self-check | ✅ `LiveWallWallpaperExtension.swift` — confirmed on-device: all 5 expected classes present |
| Registers with WallpaperAgent | ✅ confirmed via `pluginkit -m -p com.apple.wallpaper` and `extension.log` |
| Appears as a selectable collection in System Settings → Wallpaper | ✅ confirmed on-device — "LiveWall" collection with real video thumbnail, alongside built-in Aerials |
| XPC handler (`acquire`/`update`/`invalidate`/`snapshot`/...) | ✅ `WallpaperXPCHandler.swift` — full ~30-selector protocol; `acquire`/`invalidate`/`update` do real work, rest are honest stubs |
| Caller validation (`SecCodeCheckValidity` against Apple-signed WallpaperAgent) | ✅ `CallerValidation.swift` |
| Bridging header for private XPC protocols (`WallpaperExtensionXPCProtocol` et al.) | ✅ `WallpaperExtension-Bridging-Header.h` — declarations only, no memory layout assumptions |
| File-based extension logging (unified log redacts sandboxed extension output as `<private>`) | ✅ `Logging.swift` → `~/Library/Containers/com.ochurkin.LiveWall.WallpaperExtension/Data/Documents/extension.log` |
| Frame rendering (`AVSampleBufferDisplayLayer` + manual `AVAssetReader`) | ✅ `VideoRenderer.swift` (Phase 3 MVP: single video, PTS-offset loop restart — not Phosphene's full dual-reader gapless preload) — **confirmed on-device: real video plays on both desktop and Lock Screen** |
| Per-surface context keying (desktop / Settings preview / Lock Screen each get their own `CAContext`) | ✅ `WallpaperState.swift` keyed by WallpaperID UUID (`WallpaperIDProbe.swift`) — fixes a confirmed on-device bug where a Settings-preview probe's `invalidate` tore down the live desktop's only context (single-slot model) |
| Settings view model (choice shown in the picker) | ✅ `WallpaperSettingsProvider.swift` + `CodableShims.swift` — built via the **safe** `NSKeyedArchiver`/`setClass(forClassName:)` remap technique (no raw memory writes; a field mismatch fails to decode, doesn't corrupt anything) |
| Single fixed video source (`~/Movies/LiveWall/wallpaper.<ext>`) | ✅ `VideoSource.swift` — MVP scope; no multi-video library yet (Phosphene's `VideoLibrary`) |
| Snapshot generation for Lock Screen transitions (`WallpaperSnapshotXPC`) | ⏳ stub (`nil` reply) — Settings picker preview may lag the static thumbnail during transitions |
| `PlaybackPolicy` (thermal/battery/presentation-mode aware pause/resume) | ⏳ not started — renderer always plays once started, no pause on battery/fullscreen/lock parity with the desktop overlay yet |
| Spiral-of-death detection + `WallpaperAgent` auto-restart | ⏳ not started |
| Legacy `.saver` bundle (macOS 13–15 fallback) | ✅ kept as-is, unaffected by this work |

**Known MVP limitations** (deliberate scope cuts, not bugs): single video only,
no adaptive quality tiers, loop restart is a fresh `AVAssetReader` (not Phosphene's
preloaded dual-reader — a loop boundary may have a tiny hitch), no pause on
battery/fullscreen/lock (Phase 4), teardown grace timer is 15s flat (not tuned).

Old `LockScreenWallpaperManager` / `SettingsView` "Lock Screen" section (the
abandoned approach) — ⏳ still present, should be removed once the extension path
is confirmed stable over longer/normal use, to prevent accidentally re-triggering
the old bug.

#### Phased plan

**Phase 1 — Skeleton (✅ done, confirmed on-device)**
Extension target registers with the `com.apple.wallpaper` extension point, loads the
private framework, and self-checks for expected classes via `objc_getClass` (no
instances created, no memory touched). Confirmed via `pluginkit -m -p com.apple.wallpaper`
(listed alongside Apple's own Aerial/Sonoma/etc. providers and one other third-party
app, `wallspace.app.wallpaper-extension`) and via `extension.log`: dlopen succeeds,
all 5 expected classes present on macOS 26.5.

**Phase 2 — XPC acceptance (✅ done, confirmed on-device)**
`AppExtensionConfiguration.accept(connection:)` implemented for real: caller validation
via `SecCodeCheckValidity` (`CallerValidation.swift`), exported/remote interface setup,
class whitelist for the ~30 private XPC selectors (`WallpaperExtensionConfig.swift`),
full protocol implemented as honest-empty-reply stubs (`WallpaperXPCHandler.swift`) —
still no rendering. Confirmed on-device: WallpaperAgent connects, the connection is
accepted (not rejected, unlike Phase 1), and calls real methods (`provideSettingsViewModels`
observed). Protocol declarations live in `WallpaperExtension-Bridging-Header.h` — plain
Objective-C forward declarations, no memory-layout assumptions (those start in Phase 3).

**Phase 3 — Rendering MVP (✅ done, confirmed on-device)**
Single-video renderer (`VideoRenderer.swift`) driving `AVSampleBufferDisplayLayer`
manually via `AVAssetReader` (`AVPlayerLayer` does not composite in a remote
`CAContext`). `acquire` creates a real `CAContext`/`CALayer`, defers its XPC reply
until the first frame is actually composited (never a black flash), and reuses the
context on re-acquire. Settings view model built via the safe archiver-remap
technique — no raw memory writes for that part. The only raw memory pokes are the
small, bounds-checked, fail-closed `createRemoteContextXPC`/`createSnapshotXPC` in
`RuntimeHelpers.swift` (ported from Phosphene, MIT).

Found and fixed one real bug during on-device testing: an initial single-global-slot
`WallpaperState` let a Settings-preview probe's `acquire`+`invalidate` (WallpaperAgent
multiplexes desktop + preview + Lock Screen through one connection) tear down the
live desktop's only context after its 15s teardown grace fired — the desktop went
gray a few seconds after selecting LiveWall. Fixed by keying contexts per WallpaperID
UUID (`WallpaperState.swift`, `WallpaperIDProbe.swift`) so each surface owns its own
context and can't steal or kill another's. **Confirmed working: real video plays on
both the desktop and the Lock Screen simultaneously**, with the main `LiveWall.app`
fully quit (proving it's the extension rendering, not the legacy overlay window).

**Phase 3 — Rendering**
`AVSampleBufferDisplayLayer`-driven renderer (not `AVPlayerLayer`, which silently
fails inside a remote `CAContext`) with a manual `AVAssetReader` pipeline and
PTS/DTS offset for gapless looping. This is where the raw ivar-offset memory writes
(`WallpaperRemoteContextXPC`, `WallpaperSnapshotXPC` construction) become necessary —
land these behind explicit bounds checks that fail closed (as Phosphene does), and
validate on-device before considering this phase done; a wrong offset writes into
`WallpaperAgent`'s memory.

**Phase 4 — Resilience**
`PlaybackPolicy` (battery/thermal/presentation-mode), spiral-of-death detection +
auto-restart, multi-display/per-Space selection, pause-when-occluded.

**Phase 5 — UX + cleanup**
Settings UI to manage the extension's video library. Remove the abandoned
`LockScreenWallpaperManager`/Aerial-substitution code and its Settings section.

#### Expected user flow (once complete)

1. User selects a video in LiveWall.
2. LiveWall's (unsandboxed) menu bar app writes it into the extension's sandbox
   container and signals the change via Darwin notification.
3. User picks "LiveWall" as their wallpaper/Lock Screen source in System Settings →
   Wallpaper, exactly like picking a built-in Aerial.
4. macOS renders the video during idle/Lock Screen via the extension running inside
   `WallpaperAgent`; LiveWall's desktop `WallpaperWindow` remains paused while the
   session is locked (unchanged from today).

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
| **v0.6.1** | Aerial-asset-substitution Lock Screen hack — shipped, caused black screen on wake, abandoned | ❌ Reverted |
| **v0.7** | `com.apple.wallpaper` ExtensionKit target — skeleton registers + self-checks (Phase 1 of §3.5) | 🔄 |
| **v0.8** | Wallpaper extension: XPC handler, rendering, resilience (Phases 2–4 of §3.5) | ⏳ |
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
