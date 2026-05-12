import Foundation

protocol VideoPlayback: AnyObject {
    func loadVideo(url: URL)
    func play()
    func pause()
    func setGravity(_ mode: PlaybackMode)
}
