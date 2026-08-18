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
Start at Login: On/Off      ✅ `LoginItemManager` + `SMAppService`
Settings...                 ✅ SwiftUI Settings scene (⌘,)
Quit                        ✅
────────────────
CPU:  3.2%                  ✅ PerformanceMonitor
RAM:  87 MB                 ✅ PerformanceMonitor
GPU:  ~45 MB (device)       ✅ PerformanceMonitor
```

**The app is a configurator, not a player** (see §3.5): there is no Pause/Resume and no
"Pause on Battery/Fullscreen/Screen Lock" — those toggles paused the app's own desktop
overlay, which was retired once the `com.apple.wallpaper` extension proved it could render
both desktop and Lock Screen on its own (v0.7/v0.8 cutover). CPU/RAM/GPU now reflect this
app's own near-idle footprint, not video playback cost — that cost moved into `WallpaperAgent`
hosting the extension and isn't attributable per-process from here.

Performance metrics notes:
- CPU — per-process, via `mach` `task_threads` + `thread_basic_info`
- RAM — per-process physical footprint, via `task_vm_info` (`phys_footprint`)
- GPU — `MTLDevice.currentAllocatedSize` (device-wide, not per-process; sandbox limitation)
- Metrics update only when menu is open (`NSMenuDelegate`) — no background polling

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

### 3.3 Wallpaper Rendering — retired app-side approach ❌ superseded by §3.5

Through v0.6, LiveWall rendered its own borderless `NSWindow` per `NSScreen` at
`CGWindowLevelForKey(.desktopWindow)`, playing video via `AVPlayerLayer`
(`WallpaperWindowManager`/`WallpaperWindow`/`VideoWallpaperView`), and synced a static
still frame as the real desktop picture (`DesktopWallpaperSync`) so the system menu bar
picked correct contrast from it. This required `LiveWall.app` to be running at all times.

**Retired in the v0.7/v0.8 cutover** once §3.5's `com.apple.wallpaper` ExtensionKit
extension was confirmed to render the same video on both the desktop and Lock Screen via
`WallpaperAgent` — including with `LiveWall.app` fully quit. Keeping both paths running
risked exactly the two-renderers-fighting-over-one-desktop class of bug this project has
already hit once (v0.6.1). `WallpaperWindowManager`, `WallpaperWindow`, `VideoWallpaperView`,
`WallpaperWindowManaging`, `VideoPlayback`, `PlaybackCoordinator`, `SystemEventMonitor`,
`PowerModeMonitor`, `FullscreenAppMonitor`, and `DesktopWallpaperSync` were deleted from the
`LiveWall` target. `AppDelegate` now only starts the menu bar and resolves the security-scoped
bookmark for the preview thumbnail — it creates no window and renders nothing. See §3.5 and
§7 for the current architecture.

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
| `PlaybackPolicy` (thermal/battery/presentation-mode aware pause/resume) | 🔄 `PlaybackPolicy.swift` — thermal-state pause/resume done (pauses on `.serious`/`.critical`, resumes on clear, syncs newly-acquired renderers to current state); battery and presentationMode axes deferred (see below) |
| Spiral-of-death detection + `WallpaperAgent` auto-restart | ⏳ not started |
| Legacy `.saver` bundle (macOS 13–15 fallback) | ✅ kept as-is, unaffected by this work |
| Hot-reload on wallpaper change (no re-`acquire` needed) | ✅ `VideoSourceWatcher.swift` + `WallpaperState.reloadAllRenderers` — Darwin notification from `SettingsStore`, no App Group |

**Known MVP limitations** (deliberate scope cuts, not bugs): single video only,
no adaptive quality tiers, loop restart is a fresh `AVAssetReader` (not Phosphene's
preloaded dual-reader — a loop boundary may have a tiny hitch), no pause on
battery/fullscreen/lock (Phase 4), teardown grace timer is 15s flat (not tuned).

Old `LockScreenWallpaperManager` (the abandoned Aerial-substitution approach) and the
`SettingsView` "Lock Screen" section that called it — ✅ removed (deleted from
`OptimizedVideoExporter.swift` and `SettingsView.swift`) in the same pass that retired
the app-side desktop overlay (§3.3). It can no longer be triggered.

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

**Phase 4 — Resilience (🔄 in progress)**
`PlaybackPolicy` (battery/thermal/presentation-mode), spiral-of-death detection +
auto-restart, multi-display/per-Space selection, pause-when-occluded.

Thermal-state pause/resume done: `PlaybackPolicy.swift` observes
`ProcessInfo.thermalStateDidChangeNotification` and pauses every hosted
renderer (`VideoRenderer.pause()`/`resume()` — freezes the current frame via
`CMTimebaseSetRate(rate: 0)`, tears down only the `AVAssetReader`, keeps the
remote `CAContext`/layer tree live so resuming never re-triggers `acquire`)
on `.serious`/`.critical`, resumes on `.fair`/`.nominal`. A renderer created
mid-throttle (fresh `acquire`) is synced to the current decision right after
its first frame so it doesn't briefly play before the next notification.
Lives entirely inside the extension process — no dependency on `LiveWall.app`
running, same as the rest of this extension.

Deferred within this phase:
- **battery-aware pause** — the extension has no App Group entitlement to
  read `LiveWall.app`'s `pauseOnBattery` setting (separate sandbox
  containers). Pausing unconditionally on battery would silently diverge
  from that toggle's default (`false`). A minimal self-contained
  `PowerSourceObserver` (same IOKit approach as the app's
  `PowerModeMonitor`) already exists in `PlaybackPolicy.swift`, unwired,
  ready for once an App Group lands.
- **presentationMode-aware pause** — `update`'s request carries a
  presentationMode enum case name (`WallpaperXPCHandler.update`), but its
  real values (idle/lock/screensaver/etc.) are unknown without on-device
  capture. Guessing risks pausing on the wrong signal.
- spiral-of-death detection + auto-restart, multi-display/per-Space
  selection, pause-when-occluded — not started.

**Phase 5 — UX + cleanup**
Settings UI to manage the extension's video library. Remove the abandoned
`LockScreenWallpaperManager`/Aerial-substitution code and its Settings section.

#### Expected user flow (✅ current behavior)

1. User selects a video in LiveWall (menu bar → "Select Wallpaper…").
2. `SettingsStore` copies it to `~/Movies/LiveWall/wallpaper.<ext>` (readable by the
   extension via its read-only temporary-exception entitlement) and posts a Darwin
   notification (`com.ochurkin.LiveWall.wallpaperChanged`) — no App Group, no live IPC
   round-trip to the app, just a fire-and-forget signal. `VideoSourceWatcher` in the
   extension observes it and hot-swaps every currently hosted renderer
   (`WallpaperState.reloadAllRenderers`) in place, without waiting for WallpaperAgent to
   re-`acquire`.
3. User picks "LiveWall" as their wallpaper/Lock Screen source in System Settings →
   Wallpaper, exactly like picking a built-in Aerial. This is a one-time step — it
   persists in macOS's own wallpaper configuration, not in anything LiveWall owns.
4. macOS renders the video during idle/Lock Screen via the extension running inside
   `WallpaperAgent`, entirely independent of `LiveWall.app`'s process lifetime — quitting
   the app does not stop or pause playback.

`LiveWall.app`'s only job past this point is steps 1–2: pick a video, write it, signal
the extension. It never renders anything itself (§3.3).

---

### 3.4 Video Playback — owned by the extension's `VideoRenderer` (see §3.5)

| Requirement | Status |
|---|---|
| infinite loop | ✅ `VideoRenderer` — fresh `AVAssetReader` per loop, PTS/DTS offset kept monotonic |
| hardware accelerated decoding | ✅ `AVAssetReader` + `AVSampleBufferDisplayLayer` |
| muted | ✅ no audio track is read |
| pause/resume | ✅ `VideoRenderer.pause()`/`resume()` — thermal-triggered (§3.5 Phase 4); no user-facing toggle |
| display modes: Fill / Fit / Center | ❌ removed — `VideoRenderer` hardcodes `.resizeAspectFill`; no per-mode UI in `SettingsView` anymore |
| crossfade loop transition (smooth mix) | ❌ not carried over — v0.6's dual-`AVPlayerLayer` crossfade lived in the retired `VideoWallpaperView` (§3.3); `VideoRenderer`'s loop restart has a small hitch at the boundary instead (documented MVP limitation, §3.5) |

Crossfade and display-mode selection were **app-side `VideoWallpaperView` features that did
not carry over** when rendering moved to the extension (§3.3) — `VideoRenderer` is a Phase 3
MVP renderer (single video, `AVSampleBufferDisplayLayer`-driven) with neither. Re-adding
either would mean building them into `VideoRenderer` itself; not currently planned — see
§14 if revisited.

---

## 4. Settings

### 4.1 AppSettings ✅

Trimmed to just the two fields that still mean something once the app doesn't render
(§3.3): `playbackMode`, `pauseOnBattery`, `pauseWhenFullscreen`, `pauseWhenLocked`,
`crossfadeEnabled`, `crossfadeDuration`, and `batterySaverEnabled` were all removed —
each one only ever configured a now-deleted app-side component, and had no reader
left anywhere in the codebase.

| Field | Type | Status |
|---|---|---|
| `wallpaperURL` | `URL?` | ✅ persisted via security-scoped bookmark |
| `startAtLogin` | `Bool` | ✅ `LoginItemManager` + `SMAppService` |

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

Ownership moved to the extension's `VideoRenderer` (§3.5) — the app-side optimizations
this table used to list (`AVPlayerLayer`, `SystemEventMonitor`/`PlaybackCoordinator`
sleep/lock/fullscreen/battery pause) no longer apply because the app doesn't render.

| Optimization | Status |
|---|---|
| Hardware video decoding | ✅ `AVAssetReader` + `AVSampleBufferDisplayLayer` (`VideoRenderer`) |
| Lazy loading | ✅ renderer created only on `acquire`, once a frame is composited |
| Pause under thermal pressure | ✅ `PlaybackPolicy` (§3.5 Phase 4) |
| Pause on battery / fullscreen / lock | ⏳ deferred — see §3.5 Phase 4 |
| `CATransaction.disableActions` on layer updates | ✅ `VideoRenderer.resize(to:scale:)` |
| Optimized local video copy | ✅ `OptimizedVideoExporter` via AVFoundation export presets (unchanged, app-side) |

---

## 6. System Event Handling

The app no longer handles any of these — it isn't rendering, so there's nothing in it to
pause or resume. Everything below is now `WallpaperAgent`'s responsibility as host of the
extension (§3.5); LiveWall only reacts to the subset `PlaybackPolicy` explicitly implements.

| Event | Status |
|---|---|
| system sleep / wake | owned by `WallpaperAgent`, not LiveWall |
| screen sleep / wake | owned by `WallpaperAgent`, not LiveWall |
| screen lock / unlock | owned by `WallpaperAgent`, not LiveWall (renders through Lock Screen itself, §3.5) |
| monitor connected / disconnected | owned by `WallpaperAgent` — each surface re-`acquire`s with new `destSize`/`scaleFactor` |
| thermal pressure | ✅ `PlaybackPolicy` — pause/resume on `.serious`/`.critical` (§3.5 Phase 4) |
| fullscreen app open / close | ⏳ deferred — see §3.5 Phase 4 |
| power adapter changes | ⏳ deferred — see §3.5 Phase 4 |

---

## 7. Architecture ✅

Two independent processes, two targets. The app never renders (§3.3); the extension owns
all playback and keeps running with the app fully quit (§3.5).

```
LiveWall.app                      ✅ configurator only — picks a video, writes it, signals
│                                     the extension. Renders nothing.
│
├── LiveWallApp                   ✅ LiveWallApp.swift — @main, Settings scene
├── AppDelegate                   ✅ AppDelegate.swift — starts MenuBarController only
├── MenuBarController             ✅ MenuBarController.swift — NSStatusItem, Select/Settings/Quit
├── SettingsView / SettingsWindowPresenter  ✅ SwiftUI Settings window
├── SettingsStore                 ✅ SettingsStore.swift
│   ├── UserDefaults + security-scoped bookmarks
│   ├── copies picked video to ~/Movies/LiveWall/wallpaper.<ext>
│   └── posts com.ochurkin.LiveWall.wallpaperChanged (Darwin notification)
├── AppSettings                   ✅ AppSettings.swift — wallpaperURL, startAtLogin
├── OptimizedVideoExporter        ✅ optional 1080p/HEVC re-encode via AVAssetExportSession
├── PerformanceMonitor            ✅ CPU/RAM/GPU of this process (near-idle by design)
├── LoginItemManager              ✅ launch at login (SMAppService)
└── ScreenSaverInstaller          ✅ installs the legacy .saver bundle (macOS 13–15 fallback)

LiveWallWallpaperExtension.appex  ✅ com.apple.wallpaper ExtensionKit extension — all rendering,
│                                     hosted inside WallpaperAgent (§3.5)
│
├── LiveWallWallpaperExtension    ✅ entry point — dlopen + self-check, starts PlaybackPolicy
│                                     and VideoSourceWatcher
├── WallpaperExtensionConfig      ✅ accepts XPC from WallpaperAgent, caller-validated
├── WallpaperXPCHandler           ✅ acquire/update/invalidate/snapshot/settings (~30 selectors)
├── WallpaperState                ✅ per-surface CAContext registry, keyed by WallpaperID UUID
├── VideoRenderer                 ✅ AVSampleBufferDisplayLayer + manual AVAssetReader,
│                                     PTS-offset loop restart, pause()/resume()
├── VideoSource                   ✅ reads ~/Movies/LiveWall/wallpaper.<ext>
├── VideoSourceWatcher            ✅ Darwin notification → WallpaperState.reloadAllRenderers
├── PlaybackPolicy                🔄 thermal-state pause/resume; battery/presentationMode deferred
├── CallerValidation               ✅ SecCodeCheckValidity against Apple-signed WallpaperAgent
├── RuntimeHelpers                 ✅ bounds-checked remote-context/snapshot XPC construction
└── Logging                        ✅ file-based (unified log redacts sandboxed extension output)

LiveWallScreenSaver.saver         🔄 legacy compatibility path, macOS 13–15 fallback
    ├── .saver bundle target      ✅
    ├── ScreenSaverView subclass  ✅
    ├── AVPlayer (muted, looping) ✅
    └── reads the same ~/Movies/LiveWall copy ✅
```

---

## 8. Component Contracts

`WallpaperWindowManaging` and `VideoPlayback` (the app-side rendering protocols) were
deleted along with the components that implemented them (§3.3) — there is no app-side
rendering contract anymore. The extension's `VideoRenderer` (§3.5, §7) is a concrete class,
not a protocol; its public surface is `start(onFirstFrameReady:)`, `pause()`, `resume()`,
`resize(to:scale:)`, `stop()`.

### 8.1 AppSettings ✅
```swift
struct AppSettings: Codable {
    var wallpaperURL: URL?         // resolved from security-scoped bookmark via SettingsStore
    var startAtLogin: Bool
}
```

---

## 9. UX — First Launch ✅

```
1. App launches in menu bar, renders nothing
2. User selects a video wallpaper from the menu
3. LiveWall copies it to ~/Movies/LiveWall and signals the extension (§3.5)
4. User picks "LiveWall" in System Settings → Wallpaper (one-time)
5. macOS plays it — desktop and Lock Screen — via WallpaperAgent, independent
   of whether LiveWall.app is still running
```

Step 4 is the one manual step this flow still requires and LiveWall cannot skip it —
System Settings is where macOS decides which wallpaper provider is active, exactly as for
a built-in Aerial. Until it's done once, LiveWall has picked/copied a video but nothing is
visibly rendered (no app-side fallback rendering exists anymore, §3.3).

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
| **v0.7** | `com.apple.wallpaper` ExtensionKit target — skeleton, XPC, rendering MVP confirmed on-device (Phases 1–3 of §3.5) | ✅ Done |
| **v0.8** | Wallpaper extension resilience (Phase 4 of §3.5, thermal pause done, rest 🔄); **app-side desktop overlay retired** — `LiveWall.app` is now a pure configurator, extension is the sole renderer for both desktop and Lock Screen, hot-reload via Darwin notification | 🔄 |
| **v1.0** | signed, notarized, DMG, optimized | ⏳ |

---

## 11. Out of Scope ❌

online marketplace · accounts · cloud sync · AI generation · video editor ·
audio wallpapers · Windows support · web wallpapers · animated HTML

---

## 12. Technical Risks

| Risk | Mitigation |
|---|---|
| No visible wallpaper until "LiveWall" is picked in System Settings once | Documented as the required one-time step (§9); no app-side fallback rendering exists to paper over it (§3.3) |
| Multi-surface `CAContext` collision (desktop / Settings preview / Lock Screen sharing one XPC connection) | `WallpaperState` keys contexts by WallpaperID UUID — confirmed fix for an on-device bug, §3.5 Phase 3 |
| `WallpaperAgent` render pipeline instability ("spiral of death") | Not yet mitigated — spiral-of-death detection + auto-restart is un-started (§3.5 Phase 4) |
| Sandbox file access (app) | ✅ security-scoped bookmarks (`SettingsStore`) + `user-selected.read-write` entitlement |
| Sandbox file access (extension) | ✅ read-only temporary-exception entitlement scoped to `~/Movies/LiveWall/` |
| Legacy `.saver` unreliable on Tahoe | Keep it as a compatibility path; use a versioned provider abstraction |
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

Second target:          LiveWallWallpaperExtension (com.apple.product-type.extensionkit-extension)
Bundle Identifier:     com.ochurkin.LiveWall.WallpaperExtension
Entitlements:          LiveWallWallpaperExtension/LiveWallWallpaperExtension.entitlements
  com.apple.security.app-sandbox: YES
  com.apple.security.temporary-exception.files.home-relative-path.read-only: /Movies/LiveWall/
```

Distribution:
- ✅ DMG installer: `scripts/build_dmg.sh`
- ✅ default local signing: ad-hoc `CODE_SIGN_IDENTITY=-` with app entitlements
- ⏳ public distribution: Developer ID signing + notarization

---

## 14. Future Ideas (Post v1.0)

wallpaper playlists · dynamic by time of day · online packs ·
performance presets · GPU monitor · live shader wallpapers · transcoding optimizer
