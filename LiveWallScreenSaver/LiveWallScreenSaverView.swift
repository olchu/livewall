import AVFoundation
import ScreenSaver

@objc(LiveWallScreenSaverView)
final class LiveWallScreenSaverView: ScreenSaverView {
    private let sharedDefaults = UserDefaults(suiteName: "group.com.ochurkin.LiveWall")
    private let sharedWallpaperBookmarkKey = "com.ochurkin.LiveWall.sharedWallpaperBookmark"
    private let sharedWallpaperPathKey = "com.ochurkin.LiveWall.sharedWallpaperPath"

    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var loopObserver: Any?
    private var accessingURL: URL?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func layout() {
        super.layout()
        guard let layer = playerLayer, layer.frame != bounds else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = bounds
        CATransaction.commit()
    }

    override func startAnimation() {
        super.startAnimation()

        if player == nil, let url = resolveWallpaperURL() {
            loadVideo(url: url)
        }
        player?.play()
    }

    override func stopAnimation() {
        super.stopAnimation()
        player?.pause()
    }

    private func configure() {
        animationTimeInterval = 1.0 / 30.0
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    private func resolveWallpaperURL() -> URL? {
        if let data = sharedDefaults?.data(forKey: sharedWallpaperBookmarkKey) {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ), !stale {
                _ = url.startAccessingSecurityScopedResource()
                accessingURL = url
                return url
            }
        }

        guard let path = sharedDefaults?.string(forKey: sharedWallpaperPathKey) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    private func loadVideo(url: URL) {
        cleanupPlayer()

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = false

        let layer = AVPlayerLayer(player: player)
        layer.frame = bounds
        layer.videoGravity = .resizeAspectFill
        layer.backgroundColor = NSColor.black.cgColor
        layer.drawsAsynchronously = true
        self.layer?.addSublayer(layer)

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            player?.play()
        }

        self.player = player
        playerLayer = layer
        player.play()
    }

    private func cleanupPlayer() {
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
        playerLayer?.removeFromSuperlayer()
        player?.pause()
        player = nil
        playerLayer = nil
    }

    private func cleanup() {
        cleanupPlayer()
        accessingURL?.stopAccessingSecurityScopedResource()
        accessingURL = nil
    }

    deinit {
        cleanup()
    }
}
