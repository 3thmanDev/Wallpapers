import Foundation
import UIKit

/// Keeps the collection on disk and downloads every new photo at its original size.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var library: Library
    /// How many downloads the current run started with, for the progress bar.
    @Published private(set) var batchTotal = 0

    private let folder: URL
    private var queue: [String] = []
    private var activeDownloads = 0
    private var saveTask: Task<Void, Never>?
    private static let maxDownloads = 4

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = support.appendingPathComponent("Wallpapers", isDirectory: true)
        for name in ["Originals", "Thumbs"] {
            try? FileManager.default.createDirectory(at: folder.appendingPathComponent(name, isDirectory: true), withIntermediateDirectories: true)
        }
        self.folder = folder
        if let data = try? Data(contentsOf: folder.appendingPathComponent("library.json")),
           let saved = try? JSONDecoder().decode(Library.self, from: data) {
            library = saved
        } else {
            library = Library()
        }
        queue = library.wallpapers.filter { !$0.isDownloaded && !$0.failed }.map(\.id)
        batchTotal = queue.count
        pumpDownloads()
    }

    var batchProgress: Double {
        guard batchTotal > 0 else { return 0 }
        return Double(batchTotal - library.pendingCount) / Double(batchTotal)
    }

    func originalFile(_ wallpaper: Wallpaper) -> URL {
        folder.appendingPathComponent("Originals/\(wallpaper.id).\(wallpaper.fileExtension)")
    }

    func thumbnailFile(_ id: String) -> URL {
        folder.appendingPathComponent("Thumbs/\(id).jpg")
    }

    /// Returns how many of the photos were new. Imports skip photos the user deleted;
    /// a pasted link (`reviveDeleted`) brings them back.
    @discardableResult
    func add(_ wallpapers: [Wallpaper], reviveDeleted: Bool) -> Int {
        guard !wallpapers.isEmpty else { return 0 }
        var updated = library
        let added = updated.add(wallpapers, reviveDeleted: reviveDeleted)
        guard updated != library else { return 0 }
        if library.pendingCount == 0 { batchTotal = 0 }
        library = updated
        batchTotal += added.count
        queue.append(contentsOf: added)
        pumpDownloads()
        scheduleSave()
        return added.count
    }

    func delete(_ ids: Set<String>) {
        for id in ids {
            if let wallpaper = library.wallpaper(id) {
                try? FileManager.default.removeItem(at: originalFile(wallpaper))
            }
            try? FileManager.default.removeItem(at: thumbnailFile(id))
            ImageCache.shared.remove("thumb-\(id)")
            ImageCache.shared.remove("full-\(id)")
        }
        queue.removeAll { ids.contains($0) }
        library.remove(ids)
        scheduleSave()
    }

    func retryFailed() {
        let failed = library.wallpapers.filter(\.failed).map(\.id)
        guard !failed.isEmpty else { return }
        var updated = library
        for id in failed {
            updated.update(id) { $0.failed = false }
        }
        if library.pendingCount == 0 { batchTotal = 0 }
        library = updated
        batchTotal += failed.count
        queue.append(contentsOf: failed)
        pumpDownloads()
        scheduleSave()
    }

    func save() {
        saveTask?.cancel()
        guard let data = try? JSONEncoder().encode(library) else { return }
        try? data.write(to: folder.appendingPathComponent("library.json"), options: .atomic)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func pumpDownloads() {
        while activeDownloads < Self.maxDownloads, !queue.isEmpty {
            let id = queue.removeFirst()
            guard let wallpaper = library.wallpaper(id), !wallpaper.isDownloaded else { continue }
            activeDownloads += 1
            let original = originalFile(wallpaper)
            let thumbnail = thumbnailFile(id)
            Task {
                let size = await Self.download(wallpaper, to: original, thumbnail: thumbnail)
                activeDownloads -= 1
                library.update(id) { wallpaper in
                    if let size {
                        wallpaper.isDownloaded = true
                        wallpaper.failed = false
                        wallpaper.width = size.width
                        wallpaper.height = size.height
                    } else {
                        wallpaper.failed = true
                    }
                }
                scheduleSave()
                pumpDownloads()
            }
        }
    }

    /// Runs off the main thread. Falls back to X's large size if the original is refused.
    nonisolated private static func download(_ wallpaper: Wallpaper, to original: URL, thumbnail: URL) async -> (width: Int, height: Int)? {
        for size in ["orig", "large"] {
            let url = TwitterMedia.originalURL(id: wallpaper.id, fileExtension: wallpaper.fileExtension, size: size)
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let small = ImageTools.thumbnail(from: data, maxPixel: 720) else { continue }
            do {
                try data.write(to: original, options: .atomic)
                try small.jpeg.write(to: thumbnail, options: .atomic)
            } catch {
                return nil
            }
            return (small.width, small.height)
        }
        return nil
    }
}
