import AppKit
import AVFoundation

final class VideoWallpaperView: NSView, VideoPlayback {

    // MARK: - Looper mode (default)
    private var queuePlayer: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?

    // MARK: - Crossfade mode
    private var playerA: AVPlayer?
    private var playerB: AVPlayer?
    private var layerA: AVPlayerLayer?
    private var layerB: AVPlayerLayer?
    private var isAActive = true
    private var crossfadeObserver: Any?
    private var isTransitioning = false
    private var detectedDuration: Double = 0

    // MARK: - Shared state
    private var playbackRequested = true
    private var currentURL: URL?
    private var crossfadeEnabled = false
    private var crossfadeDuration: Double = 1.5

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
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer?.frame = bounds
        layerA?.frame = bounds
        layerB?.frame = bounds
        CATransaction.commit()
    }

    // MARK: - VideoPlayback

    func loadVideo(url: URL) {
        cleanup()
        currentURL = url

        if crossfadeEnabled {
            loadCrossfadeMode(url: url)
        } else {
            loadLooperMode(url: url)
        }
    }

    func play() {
        playbackRequested = true
        if crossfadeEnabled {
            activePlayer?.play()
        } else {
            queuePlayer?.play()
        }
    }

    func pause() {
        playbackRequested = false
        if crossfadeEnabled {
            playerA?.pause()
            playerB?.pause()
        } else {
            queuePlayer?.pause()
        }
    }

    func setGravity(_ mode: PlaybackMode) {
        let gravity: AVLayerVideoGravity = switch mode {
        case .fill:   .resizeAspectFill
        case .fit:    .resizeAspect
        case .center: .resize
        }
        playerLayer?.videoGravity = gravity
        layerA?.videoGravity = gravity
        layerB?.videoGravity = gravity
    }

    func setCrossfade(enabled: Bool, duration: Double) {
        let modeChanged = enabled != crossfadeEnabled
        crossfadeEnabled = enabled
        crossfadeDuration = duration

        if modeChanged, let url = currentURL {
            loadVideo(url: url)
        } else if crossfadeEnabled {
            // Duration changed — reinstall boundary observer with new timing
            removeCrossfadeObserver()
            installCrossfadeObserver()
        }
    }

    // MARK: - Looper mode

    private func loadLooperMode(url: URL) {
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

        queuePlayer = player
        playerLooper = looper
        playerLayer = layer

        if playbackRequested { player.play() }
    }

    // MARK: - Crossfade mode

    private func loadCrossfadeMode(url: URL) {
        let asset = AVURLAsset(url: url)

        let a = makePlayer(asset: asset)
        let b = makePlayer(asset: asset)

        let la = makePlayerLayer(player: a, opacity: 1)
        let lb = makePlayerLayer(player: b, opacity: 0)

        wantsLayer = true
        self.layer?.addSublayer(la)
        self.layer?.addSublayer(lb)

        playerA = a
        playerB = b
        layerA = la
        layerB = lb
        isAActive = true

        Task { [weak self] in
            guard let self else { return }
            let duration = (try? await asset.load(.duration))?.seconds ?? 0
            await MainActor.run {
                self.detectedDuration = duration
                self.installCrossfadeObserver()
                if self.playbackRequested { a.play() }
            }
        }
    }

    private func makePlayer(asset: AVURLAsset) -> AVPlayer {
        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        player.isMuted = true
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.automaticallyWaitsToMinimizeStalling = false
        return player
    }

    private func makePlayerLayer(player: AVPlayer, opacity: Float) -> AVPlayerLayer {
        let layer = AVPlayerLayer(player: player)
        layer.frame = bounds
        layer.videoGravity = .resizeAspectFill
        layer.backgroundColor = NSColor.black.cgColor
        layer.drawsAsynchronously = true
        layer.opacity = opacity
        return layer
    }

    private var activePlayer: AVPlayer? { isAActive ? playerA : playerB }
    private var standbyPlayer: AVPlayer? { isAActive ? playerB : playerA }
    private var activeLayer: AVPlayerLayer? { isAActive ? layerA : layerB }
    private var standbyLayer: AVPlayerLayer? { isAActive ? layerB : layerA }

    private func installCrossfadeObserver() {
        guard crossfadeEnabled,
              detectedDuration > 0,
              crossfadeDuration < detectedDuration * 0.5,
              let player = activePlayer else { return }

        let triggerSeconds = detectedDuration - crossfadeDuration
        let triggerTime = CMTime(seconds: triggerSeconds, preferredTimescale: 600)

        crossfadeObserver = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: triggerTime)],
            queue: .main
        ) { [weak self] in
            self?.triggerCrossfade()
        }
    }

    private func removeCrossfadeObserver() {
        guard let obs = crossfadeObserver else { return }
        activePlayer?.removeTimeObserver(obs)
        crossfadeObserver = nil
    }

    private func triggerCrossfade() {
        guard !isTransitioning else { return }
        isTransitioning = true

        standbyPlayer?.seek(to: .zero)
        standbyPlayer?.play()

        // Bring standby layer on top so it fades in over the active layer.
        // Without this, every other crossfade would be invisible (standby below active).
        activeLayer?.zPosition = 0
        standbyLayer?.zPosition = 1

        // Only fade IN the standby layer — active stays fully opaque so the black
        // background never shows through both semi-transparent layers at once.
        CATransaction.begin()
        CATransaction.setAnimationDuration(crossfadeDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        CATransaction.setCompletionBlock { [weak self] in
            self?.finalizeCrossfade()
        }
        standbyLayer?.opacity = 1
        CATransaction.commit()
    }

    private func finalizeCrossfade() {
        let oldActiveLayer = activeLayer
        let oldActivePlayer = activePlayer
        removeCrossfadeObserver()

        isAActive.toggle()

        // Hide and reset the old active layer/player now that new one is fully visible
        oldActiveLayer?.opacity = 0
        oldActivePlayer?.pause()
        oldActivePlayer?.seek(to: .zero)

        isTransitioning = false
        installCrossfadeObserver()
    }

    // MARK: - Helpers

    private func configureBackingLayer() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    private func cleanup() {
        removeCrossfadeObserver()
        playerLooper?.disableLooping()
        playerLooper = nil
        playerLayer?.removeFromSuperlayer()
        queuePlayer?.pause()
        queuePlayer = nil
        playerLayer = nil

        playerA?.pause()
        playerB?.pause()
        playerA = nil
        playerB = nil
        layerA?.removeFromSuperlayer()
        layerB?.removeFromSuperlayer()
        layerA = nil
        layerB = nil

        isAActive = true
        isTransitioning = false
        detectedDuration = 0
    }

    deinit { cleanup() }
}
