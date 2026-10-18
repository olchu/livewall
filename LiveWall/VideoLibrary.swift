import Foundation
import UniformTypeIdentifiers

struct LibraryVideo: Identifiable, Hashable, Sendable {
    let url: URL
    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

/// One carousel row: the videos directly in the library folder, or everything
/// inside one of its subfolders.
struct LibrarySection: Identifiable, Equatable, Sendable {
    let folderURL: URL
    let videos: [LibraryVideo]
    var id: URL { folderURL }
    var title: String { folderURL.lastPathComponent }
}

enum VideoLibrary {
    /// Scan `folder` into sections (SPEC.md §3.1): its own videos first, then
    /// one section per immediate subfolder, holding every video found anywhere
    /// inside it. Empty sections are omitted; everything is sorted by name.
    /// Does file I/O — call off the main thread.
    static func sections(in folder: URL) -> [LibrarySection] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        guard let children = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
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

        let sections = [LibrarySection(folderURL: folder, videos: sortedByName(rootVideos))]
            + sortedByName(subfolders).map { LibrarySection(folderURL: $0, videos: sortedByName(videos(inside: $0))) }
        return sections.filter { !$0.videos.isEmpty }
    }

    static func isSupportedVideo(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if SettingsStore.supportedVideoExtensions.contains(ext) { return true }
        guard let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .mpeg4Movie) || type.conforms(to: .quickTimeMovie)
    }

    private static func videos(inside folder: URL) -> [LibraryVideo] {
        let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        var videos: [LibraryVideo] = []
        while let url = enumerator?.nextObject() as? URL {
            if !isFolder(url), isSupportedVideo(url) { videos.append(LibraryVideo(url: url)) }
        }
        return videos
    }

    /// A real folder — packages (`.app`, `.photoslibrary`) count as files.
    private static func isFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }

    private static func sortedByName(_ urls: [URL]) -> [URL] {
        urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func sortedByName(_ videos: [LibraryVideo]) -> [LibraryVideo] {
        videos.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
