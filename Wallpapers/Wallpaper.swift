import Foundation

enum WallpaperSource: String, Codable, CaseIterable {
    case bookmarks
    case likes
    case link

    var title: String {
        switch self {
        case .bookmarks: return "العلامات المرجعية"
        case .likes: return "الإعجابات"
        case .link: return "روابط"
        }
    }
}

struct Wallpaper: Codable, Identifiable, Equatable {
    /// X's file name for the photo, e.g. "HV8fJNdaYAA4Y2D". The same photo reached
    /// through bookmarks, likes or a pasted link always gets the same id.
    let id: String
    var fileExtension: String
    var tweetURL: URL?
    var width: Int
    var height: Int
    var sources: Set<WallpaperSource>
    var addedAt: Date
    var isDownloaded = false
    var failed = false

    var remoteURL: URL { TwitterMedia.originalURL(id: id, fileExtension: fileExtension) }

    var isPortrait: Bool { height > width }

    init?(photoURL: String, tweetURL: String?, width: Int, height: Int, source: WallpaperSource, addedAt: Date) {
        guard let media = TwitterMedia.parse(photoURL) else { return nil }
        id = media.id
        fileExtension = media.fileExtension
        self.tweetURL = tweetURL.flatMap(TweetLink.tweetURL(from:))
        self.width = width
        self.height = height
        sources = [source]
        self.addedAt = addedAt
    }
}

enum TwitterMedia {
    /// Reads X photo addresses in every form the site and the APIs use:
    /// `…/media/ID.jpg`, `…/media/ID.jpg?name=orig`, `…/media/ID?format=png&name=small`, `…/media/ID.jpg:large`.
    static func parse(_ string: String) -> (id: String, fileExtension: String)? {
        guard let components = URLComponents(string: string),
              components.host == "pbs.twimg.com",
              components.path.hasPrefix("/media/") else { return nil }
        var name = String(components.path.dropFirst("/media/".count))
        if let colon = name.firstIndex(of: ":") {
            name = String(name[..<colon])
        }
        var fileExtension = components.queryItems?.first(where: { $0.name == "format" })?.value
        if let dot = name.lastIndex(of: ".") {
            fileExtension = fileExtension ?? String(name[name.index(after: dot)...])
            name = String(name[..<dot])
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard !name.isEmpty, name.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        let normalized = (fileExtension ?? "jpg").lowercased()
        return (name, ["jpg", "jpeg", "png", "webp"].contains(normalized) ? normalized : "jpg")
    }

    /// The full-size file as it was uploaded, not the resized copy the timeline shows.
    static func originalURL(id: String, fileExtension: String, size: String = "orig") -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "pbs.twimg.com"
        components.path = "/media/\(id)"
        components.queryItems = [
            URLQueryItem(name: "format", value: fileExtension),
            URLQueryItem(name: "name", value: size),
        ]
        return components.url!
    }
}

enum TweetLink {
    private static let pattern = try! NSRegularExpression(
        pattern: #"(?:^|[^a-z0-9.])(?:(?:www|mobile)\.)?(?:twitter|x|fxtwitter|vxtwitter|fixupx|fixvx|twittpr)\.com/(?:[A-Za-z0-9_]{1,20}|i(?:/web)?)/status(?:es)?/([0-9]{5,25})"#,
        options: [.caseInsensitive]
    )

    /// Every tweet id in the text, in order and without repeats, so several pasted links work at once.
    static func statusIDs(in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        var ids: [String] = []
        for match in pattern.matches(in: text, range: range) {
            guard let idRange = Range(match.range(at: 1), in: text) else { continue }
            let id = String(text[idRange])
            if !ids.contains(id) { ids.append(id) }
        }
        return ids
    }

    /// `https://x.com/user/status/123/photo/1` → `https://x.com/user/status/123`.
    static func tweetURL(from string: String) -> URL? {
        guard var components = URLComponents(string: string),
              let host = components.host,
              host == "x.com" || host == "twitter.com" || host.hasSuffix(".twitter.com") else { return nil }
        let parts = components.path.split(separator: "/")
        guard let statusIndex = parts.firstIndex(where: { $0 == "status" || $0 == "statuses" }),
              statusIndex + 1 < parts.count else { return nil }
        components.host = "x.com"
        components.path = "/" + parts[...(statusIndex + 1)].joined(separator: "/")
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

/// Everything the app keeps about the collection. Value type so the merge rules can be
/// checked by `Tests/main.swift` without the app.
struct Library: Codable, Equatable {
    private(set) var wallpapers: [Wallpaper] = []
    /// Photos the user deleted. Importing the same likes again won't bring them back;
    /// pasting their link on purpose does.
    private(set) var deletedIDs: Set<String> = []

    /// Adds the photos that are new and merges the rest into what is already there.
    /// Returns the ids that were added.
    @discardableResult
    mutating func add(_ incoming: [Wallpaper], reviveDeleted: Bool) -> [String] {
        var added: [String] = []
        for wallpaper in incoming {
            if let index = wallpapers.firstIndex(where: { $0.id == wallpaper.id }) {
                wallpapers[index].sources.formUnion(wallpaper.sources)
                if wallpapers[index].tweetURL == nil { wallpapers[index].tweetURL = wallpaper.tweetURL }
                if wallpapers[index].width == 0 {
                    wallpapers[index].width = wallpaper.width
                    wallpapers[index].height = wallpaper.height
                }
                continue
            }
            if deletedIDs.contains(wallpaper.id) {
                guard reviveDeleted else { continue }
                deletedIDs.remove(wallpaper.id)
            }
            var fresh = wallpaper
            fresh.isDownloaded = false
            fresh.failed = false
            wallpapers.append(fresh)
            added.append(fresh.id)
        }
        if !added.isEmpty {
            wallpapers.sort { $0.addedAt > $1.addedAt }
        }
        return added
    }

    mutating func remove(_ ids: Set<String>) {
        wallpapers.removeAll { ids.contains($0.id) }
        deletedIDs.formUnion(ids)
    }

    mutating func update(_ id: String, _ change: (inout Wallpaper) -> Void) {
        guard let index = wallpapers.firstIndex(where: { $0.id == id }) else { return }
        change(&wallpapers[index])
    }

    func wallpaper(_ id: String) -> Wallpaper? {
        wallpapers.first { $0.id == id }
    }

    /// Already imported from this list, or deleted by the user.
    func hasSeen(_ id: String, from source: WallpaperSource) -> Bool {
        deletedIDs.contains(id) || wallpaper(id)?.sources.contains(source) == true
    }

    var pendingCount: Int { wallpapers.filter { !$0.isDownloaded && !$0.failed }.count }
    var failedCount: Int { wallpapers.filter(\.failed).count }

    func count(of source: WallpaperSource) -> Int {
        wallpapers.filter { $0.sources.contains(source) }.count
    }
}

/// Decides when a "new only" import can stop. X lists bookmarks and likes newest first,
/// so once a long run of photos is all already in the library, the rest is too.
struct CatchUpTracker {
    static let knownRunToStop = 30
    private(set) var knownRun = 0

    /// Feed each page in list order, before adding it to the library.
    /// Returns true once enough known photos came in a row.
    mutating func feed(_ wallpapers: [Wallpaper], source: WallpaperSource, library: Library) -> Bool {
        for wallpaper in wallpapers {
            knownRun = library.hasSeen(wallpaper.id, from: source) ? knownRun + 1 : 0
        }
        return knownRun >= Self.knownRunToStop
    }
}
