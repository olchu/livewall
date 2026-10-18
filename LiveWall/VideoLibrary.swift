import Foundation
import UniformTypeIdentifiers

struct LibraryVideo: Identifiable, Hashable, Sendable {
    /// Standardized, so it compares directly against `LibraryModel.currentWallpaperURL`.
    let url: URL
    let name: String
    var id: URL { url }

    init(url: URL) {
        self.url = url.standardizedFileURL
        name = url.deletingPathExtension().lastPathComponent
    }
}

/// One row of the library: the videos directly in the library folder, or
/// everything inside one of its subfolders.
struct LibrarySection: Identifiable, Equatable, Sendable {
    let folderURL: URL
    let videos: [LibraryVideo]
    var id: URL { folderURL }
    var title: String { folderURL.lastPathComponent }
}

enum VideoLibrary {
    private static let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
    private static let byName = KeyPathComparator(\LibraryVideo.name, comparator: .localizedStandard)

    /// Scan `folder` into sections (SPEC.md §3.1): its own videos first, then
    /// one section per immediate subfolder, holding every video found anywhere
    /// inside it. Empty sections are omitted; everything is sorted by name.
    /// Does file I/O — call off the main thread.
    static func sections(in folder: URL) -> [LibrarySection] {
        guard let children = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles]) else {
            return []
        }

        var rootVideos: [LibraryVideo] = []
        var subfolders: [URL] = []
        for url in children {
            if isFolder(url) {
                subfolders.append(url)
            } else if isSupportedVideo(url) {
                rootVideos.append(LibraryVideo(url: url))
            }
        }

        let subfolderSections = subfolders
            .sorted(using: KeyPathComparator(\.lastPathComponent, comparator: .localizedStandard))
            .map { LibrarySection(folderURL: $0, videos: videos(inside: $0).sorted(using: byName)) }
        return ([LibrarySection(folderURL: folder, videos: rootVideos.sorted(using: byName))] + subfolderSections)
            .filter { !$0.videos.isEmpty }
    }

    /// mp4, mov and m4v all conform to one of these.
    private static func isSupportedVideo(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .mpeg4Movie) || type.conforms(to: .quickTimeMovie)
    }

    private static func videos(inside folder: URL) -> [LibraryVideo] {
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return []
        }
        var videos: [LibraryVideo] = []
        for case let url as URL in enumerator where !isFolder(url) && isSupportedVideo(url) {
            videos.append(LibraryVideo(url: url))
        }
        return videos
    }

    /// A real folder — packages (`.app`, `.photoslibrary`) count as files.
    private static func isFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: Set(resourceKeys))
        return values?.isDirectory == true && values?.isPackage != true
    }
}
