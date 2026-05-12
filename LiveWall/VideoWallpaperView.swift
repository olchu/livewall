import AppKit
import AVFoundation

final class VideoWallpaperView: NSView, VideoPlayback {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var loopObserver: Any?

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Set up layer backing once — avoids layout recursion if loadVideo is called during layout
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
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
