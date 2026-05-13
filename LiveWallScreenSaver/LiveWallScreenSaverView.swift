import Darwin
import os
import ScreenSaver
import AVFoundation

private let saverLog = OSLog(subsystem: "com.ochurkin.LiveWall.ScreenSaver", category: "player")
private func slog(_ msg: String) {
    os_log("%{public}@", log: saverLog, type: .default, msg)
}

@objc(LiveWallScreenSaverView)
final class LiveWallScreenSaverView: ScreenSaverView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var endObserver: Any?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        slog("init isPreview=\(isPreview)")
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        animationTimeInterval = 1.0 / 30.0
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        animationTimeInterval = 1.0 / 30.0
    }

    // MARK: - Lifecycle

    override func startAnimation() {
        super.startAnimation()
        slog("startAnimation bounds=\(NSStringFromRect(bounds))")
        ensureFullSize()
        setupPlayer()
    }

    override func stopAnimation() {
        super.stopAnimation()
        slog("stopAnimation")
        teardownPlayer()
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        playerLayer?.frame = bounds
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        playerLayer?.frame = bounds
    }

    // bounds = 0x0 at init in legacyScreenSaver — force screen size.
    private func ensureFullSize() {
        guard bounds.width <= 1 || bounds.height <= 1 else { return }
        let size = NSScreen.main?.frame.size ?? NSSize(width: 1920, height: 1080)
        slog("ensureFullSize: \(size.width)x\(size.height)")
        setFrameSize(size)
    }

    // MARK: - Player

    private func setupPlayer() {
        guard player == nil else { return }
        guard let url = resolveWallpaperURL() else {
            slog("setupPlayer: no video found")
            return
        }

        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.isMuted = true

        let pl = AVPlayerLayer(player: p)
        pl.videoGravity = .resizeAspectFill
        pl.frame = bounds
        layer?.addSublayer(pl)

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak p] _ in
            p?.seek(to: .zero)
            p?.play()
        }

        p.play()
        slog("setupPlayer: playing \(url.lastPathComponent)")

        player = p
        playerLayer = pl
    }

    private func teardownPlayer() {
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
        player?.pause()
        playerLayer?.removeFromSuperlayer()
        player = nil
        playerLayer = nil
    }

    // MARK: - URL resolution

    private func resolveWallpaperURL() -> URL? {
        // legacyScreenSaver container has Movies -> ~/Movies symlink.
        // getpwuid() gives the real home path, bypassing sandbox redirection.
        guard let pw = getpwuid(getuid()), let pwDir = pw.pointee.pw_dir else {
            slog("getpwuid failed")
            return nil
        }
        let base = String(cString: pwDir) + "/Movies/LiveWall"
        for ext in ["mp4", "mov", "m4v"] {
            let url = URL(fileURLWithPath: "\(base)/wallpaper.\(ext)")
            if FileManager.default.fileExists(atPath: url.path) {
                slog("found: \(url.path)")
                return url
            }
        }
        slog("no wallpaper in ~/Movies/LiveWall")
        return nil
    }

    deinit {
        teardownPlayer()
    }
}
