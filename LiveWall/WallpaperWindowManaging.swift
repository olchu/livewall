import Foundation

protocol WallpaperWindowManaging: AnyObject {
    func setupWallpaperWindows()
    func destroyWallpaperWindows()
    func reloadWallpaper()
    func pause()
    func resume()
    func handleDisplayChange()
}
