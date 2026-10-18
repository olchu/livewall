import AVFoundation
import SwiftUI

/// Muted, looping playback for a card's hover preview — a UI preview inside
/// the app's own window only. Wallpaper rendering stays in the extension
/// (SPEC.md §3.5). Before its first frame the layer is transparent, so the
/// card's thumbnail underneath shows through instead of a black flash.
struct LoopingVideoView: NSViewRepresentable {
    let url: URL
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> PlayerView {
        let view = PlayerView(cornerRadius: cornerRadius)
        view.play(url)
        return view
    }

    func updateNSView(_ view: PlayerView, context: Context) {}

    static func dismantleNSView(_ view: PlayerView, coordinator: ()) {
        view.stop()
    }

    final class PlayerView: NSView {
        private let playerLayer = AVPlayerLayer()
        private var looper: AVPlayerLooper?

        init(cornerRadius: CGFloat) {
            super.init(frame: .zero)
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.cornerRadius = cornerRadius
            playerLayer.cornerCurve = .continuous
            playerLayer.masksToBounds = true
            layer = playerLayer
            wantsLayer = true
        }

        required init?(coder: NSCoder) { fatalError() }

        /// Display only — clicks fall through to the card underneath.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func play(_ url: URL) {
            let player = AVQueuePlayer()
            player.isMuted = true
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            playerLayer.player = player
            player.play()
        }

        func stop() {
            playerLayer.player?.pause()
            playerLayer.player = nil
            looper = nil
        }
    }
}
