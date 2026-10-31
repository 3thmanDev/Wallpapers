import Foundation

/// A message from `Harvest.txt` inside the X page.
struct HarvestMessage: Decodable {
    struct Photo: Decodable {
        let url: String
        let tweetUrl: String?
        let width: Int?
        let height: Int?
    }

    let event: String
    var op: String?
    var entries: Int?
    var photos: [Photo]?
    var loggedIn: Bool?
    var running: Bool?
    var reason: String?
    var status: Int?

    static func decode(_ json: String) -> HarvestMessage? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(HarvestMessage.self, from: data)
    }

    /// Which of the user's lists the page came from: "Likes", or "Bookmarks" and its folders.
    var source: WallpaperSource? {
        guard let op else { return nil }
        if op == "Likes" { return .likes }
        if op.hasPrefix("Bookmark") { return .bookmarks }
        return nil
    }

    /// Newest first, the way X lists them: each photo is dated a moment before the one above it.
    func wallpapers(startingAt date: Date, step: TimeInterval = 0.001) -> [Wallpaper] {
        guard let source, let photos else { return [] }
        return photos.enumerated().compactMap { index, photo in
            Wallpaper(
                photoURL: photo.url,
                tweetURL: photo.tweetUrl,
                width: photo.width ?? 0,
                height: photo.height ?? 0,
                source: source,
                addedAt: date.addingTimeInterval(-Double(index) * step)
            )
        }
    }
}

/// The two public services that turn a tweet link into its photos without signing in.
enum TweetLookup {
    /// api.fxtwitter.com, the service behind fxtwitter.com link previews.
    struct FxResponse: Decodable {
        struct Tweet: Decodable {
            struct Media: Decodable {
                struct Photo: Decodable {
                    let url: String
                    let width: Int?
                    let height: Int?
                }
                let photos: [Photo]?
            }
            let url: String?
            let media: Media?
        }
        let code: Int?
        let tweet: Tweet?
    }

    /// cdn.syndication.twimg.com, the endpoint X's own embedded tweets use.
    struct SyndicationResponse: Decodable {
        struct Media: Decodable {
            struct Size: Decodable {
                let width: Int
                let height: Int
            }
            let type: String
            let media_url_https: String
            let original_info: Size?
        }
        struct User: Decodable {
            let screen_name: String?
        }
        let id_str: String?
        let user: User?
        let mediaDetails: [Media]?
    }

    static func fxURL(statusID: String) -> URL {
        URL(string: "https://api.fxtwitter.com/status/\(statusID)")!
    }

    static func syndicationURL(statusID: String) -> URL {
        var components = URLComponents(string: "https://cdn.syndication.twimg.com/tweet-result")!
        components.queryItems = [
            URLQueryItem(name: "id", value: statusID),
            URLQueryItem(name: "token", value: syndicationToken(statusID: statusID)),
        ]
        return components.url!
    }

    /// The same value X's embed script sends: `(id / 1e15 * π)` in base 36, without zeros and the dot.
    static func syndicationToken(statusID: String) -> String {
        let value = (Double(statusID) ?? 0) / 1e15 * Double.pi
        let digits = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        var whole = Int(value)
        var fraction = value - Double(whole)
        var text = ""
        repeat {
            text.insert(digits[whole % 36], at: text.startIndex)
            whole /= 36
        } while whole > 0
        for _ in 0..<11 {
            fraction *= 36
            let digit = Int(fraction)
            text.append(digits[digit])
            fraction -= Double(digit)
        }
        return text.replacingOccurrences(of: "0", with: "")
    }

    static func wallpapers(fromFx data: Data, statusID: String, addedAt: Date) -> [Wallpaper] {
        guard let response = try? JSONDecoder().decode(FxResponse.self, from: data),
              let tweet = response.tweet else { return [] }
        let tweetURL = tweet.url ?? "https://x.com/i/status/\(statusID)"
        return (tweet.media?.photos ?? []).enumerated().compactMap { index, photo in
            Wallpaper(
                photoURL: photo.url,
                tweetURL: tweetURL,
                width: photo.width ?? 0,
                height: photo.height ?? 0,
                source: .link,
                addedAt: addedAt.addingTimeInterval(-Double(index) * 0.001)
            )
        }
    }

    static func wallpapers(fromSyndication data: Data, statusID: String, addedAt: Date) -> [Wallpaper] {
        guard let response = try? JSONDecoder().decode(SyndicationResponse.self, from: data) else { return [] }
        let user = response.user?.screen_name ?? "i"
        let tweetURL = "https://x.com/\(user)/status/\(response.id_str ?? statusID)"
        return (response.mediaDetails ?? []).filter { $0.type == "photo" }.enumerated().compactMap { index, media in
            Wallpaper(
                photoURL: media.media_url_https,
                tweetURL: tweetURL,
                width: media.original_info?.width ?? 0,
                height: media.original_info?.height ?? 0,
                source: .link,
                addedAt: addedAt.addingTimeInterval(-Double(index) * 0.001)
            )
        }
    }
}
