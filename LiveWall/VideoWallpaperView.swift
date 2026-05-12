import AppKit
import AVFoundation

final class VideoWallpaperView: NSView, VideoPlayback {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var loopObserver: Any?

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
        wantsLayer = true
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
        self.playerLayer = layer
        player.play()
    }

    func play() {
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    func setGravity(_ mode: PlaybackMode) {
        switch mode {
        case .fill:   playerLayer?.videoGravity = .resizeAspectFill
        case .fit:    playerLayer?.videoGravity = .resizeAspect
        case .center: playerLayer?.videoGravity = .resizeAspect
        }
    }

    private func configureBackingLayer() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    private func cleanup() {
        if let obs = loopObserver {
            NotificationCenter.default.removeObserver(obs)
            loopObserver = nil
        }
        playerLayer?.removeFromSuperlayer()
        player?.pause()
        player = nil
        playerLayer = nil
    }

    deinit { cleanup() }
}
