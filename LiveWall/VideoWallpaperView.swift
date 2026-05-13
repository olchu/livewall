import AppKit
import AVFoundation

final class VideoWallpaperView: NSView, VideoPlayback {
    private var queuePlayer: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?
    private var playbackRequested = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureBackingLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureBackingLayer()
    }

    override func layout() {
        super.layout()
        guard let layer = playerLayer, layer.frame != bounds else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = bounds
        CATransaction.commit()
    }

    func loadVideo(url: URL) {
        cleanup()

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        let player = AVQueuePlayer()
        player.isMuted = true
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.automaticallyWaitsToMinimizeStalling = false

        let looper = AVPlayerLooper(player: player, templateItem: item)

        let layer = AVPlayerLayer(player: player)
        layer.frame = bounds
        layer.videoGravity = .resizeAspectFill
        layer.backgroundColor = NSColor.black.cgColor
        layer.drawsAsynchronously = true
        wantsLayer = true
        self.layer?.addSublayer(layer)

        self.queuePlayer = player
        self.playerLooper = looper
        self.playerLayer = layer

        if playbackRequested {
            player.play()
        }
    }

    func play() {
        playbackRequested = true
        queuePlayer?.play()
    }

    func pause() {
        playbackRequested = false
        queuePlayer?.pause()
    }

    func setGravity(_ mode: PlaybackMode) {
        switch mode {
        case .fill:   playerLayer?.videoGravity = .resizeAspectFill
        case .fit:    playerLayer?.videoGravity = .resizeAspect
        case .center: playerLayer?.videoGravity = .resize
        }
    }

    private func configureBackingLayer() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    private func cleanup() {
        playerLooper?.disableLooping()
        playerLooper = nil
        playerLayer?.removeFromSuperlayer()
        queuePlayer?.pause()
        queuePlayer = nil
        playerLayer = nil
    }

    deinit { cleanup() }
}
