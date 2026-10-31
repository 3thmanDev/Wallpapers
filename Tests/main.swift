// Checks the parts of the app that don't need an iPhone: reading X photo and tweet
// links, the messages from Harvest.js, the two link services, and the library merge rules.
//   swiftc Wallpapers/Wallpaper.swift Wallpapers/TweetSources.swift Tests/main.swift -o wallpaper-check && ./wallpaper-check
import Foundation

var failures = 0
var checks = 0

func check(_ condition: Bool, _ label: String) {
    checks += 1
    if condition {
        print("ok    \(label)")
    } else {
        failures += 1
        print("FAIL  \(label)")
    }
}

// MARK: - Photo addresses

let forms = [
    "https://pbs.twimg.com/media/HV8fJNdaYAA4Y2D.jpg",
    "https://pbs.twimg.com/media/HV8fJNdaYAA4Y2D.jpg?name=orig",
    "https://pbs.twimg.com/media/HV8fJNdaYAA4Y2D?format=jpg&name=small",
    "https://pbs.twimg.com/media/HV8fJNdaYAA4Y2D.jpg:large",
]
for form in forms {
    let parsed = TwitterMedia.parse(form)
    check(parsed?.id == "HV8fJNdaYAA4Y2D" && parsed?.fileExtension == "jpg", "photo id from \(form)")
}
check(TwitterMedia.parse("https://pbs.twimg.com/media/AbC-12_x?format=png&name=900x900")?.fileExtension == "png", "png format from the query")
check(TwitterMedia.parse("https://pbs.twimg.com/profile_images/1/a.jpg") == nil, "profile pictures are not wallpapers")
check(TwitterMedia.parse("https://example.com/media/HV8fJNdaYAA4Y2D.jpg") == nil, "other sites are refused")
check(
    TwitterMedia.originalURL(id: "HV8fJNdaYAA4Y2D", fileExtension: "jpg").absoluteString
        == "https://pbs.twimg.com/media/HV8fJNdaYAA4Y2D?format=jpg&name=orig",
    "original-size download address"
)

// MARK: - Tweet links

check(TweetLink.statusIDs(in: "https://x.com/someone/status/2116444614647583222?s=46&t=abc") == ["2116444614647583222"], "x.com share link")
check(TweetLink.statusIDs(in: "https://twitter.com/i/web/status/1585341984679469056") == ["1585341984679469056"], "twitter.com i/web link")
check(TweetLink.statusIDs(in: "https://mobile.twitter.com/a_b/status/123456789/photo/2") == ["123456789"], "mobile link with photo number")
check(TweetLink.statusIDs(in: "شوف https://fxtwitter.com/u/status/111111 و https://vxtwitter.com/u/status/222222 و https://x.com/u/status/111111")
    == ["111111", "222222"], "several links in Arabic text, repeats dropped")
check(TweetLink.statusIDs(in: "https://x.com/someone").isEmpty, "profile link has no tweet")
check(TweetLink.statusIDs(in: "https://notx.com/u/status/123456").isEmpty, "look-alike site is refused")
check(TweetLink.tweetURL(from: "https://x.com/blvck/status/2116444614647583222/photo/1")?.absoluteString
    == "https://x.com/blvck/status/2116444614647583222", "photo link trimmed to the tweet")
check(TweetLink.tweetURL(from: "https://twitter.com/blvck/status/12345?s=20")?.absoluteString
    == "https://x.com/blvck/status/12345", "twitter.com link moved to x.com")

// MARK: - Messages from Harvest.js

let harvestJSON = """
{"event":"photos","op":"Bookmarks","entries":20,"photos":[
 {"url":"https://pbs.twimg.com/media/HV8fJNdaYAA4Y2D.jpg","tweetUrl":"https://x.com/blvck/status/2116444614647583222/photo/1","width":1981,"height":1981},
 {"url":"https://pbs.twimg.com/media/HV8fJNra0AAo106.jpg","tweetUrl":"https://x.com/blvck/status/2116444614647583222/photo/1","width":1890,"height":4096},
 {"url":"https://pbs.twimg.com/profile_images/1/x.jpg","tweetUrl":null,"width":0,"height":0}
]}
"""
let message = HarvestMessage.decode(harvestJSON)
check(message?.source == .bookmarks, "Bookmarks page maps to bookmarks")
let start = Date(timeIntervalSince1970: 1_800_000_000)
let harvested = message?.wallpapers(startingAt: start) ?? []
check(harvested.count == 2, "two photos kept, the odd address dropped (got \(harvested.count))")
check(harvested.first?.addedAt == start && (harvested.last?.addedAt ?? start) < start, "first photo on the page sorts first")
check(harvested.last?.isPortrait == true && harvested.first?.isPortrait == false, "portrait detection")
check(harvested.first?.tweetURL?.absoluteString == "https://x.com/blvck/status/2116444614647583222", "tweet link without /photo/1")
check(HarvestMessage.decode(#"{"event":"photos","op":"Likes","entries":0,"photos":[]}"#)?.source == .likes, "Likes page maps to likes")
check(HarvestMessage.decode(#"{"event":"photos","op":"BookmarkFolderTimeline","photos":[]}"#)?.source == .bookmarks, "bookmark folders map to bookmarks")
check(HarvestMessage.decode(#"{"event":"session","loggedIn":true}"#)?.loggedIn == true, "session message")

// MARK: - Link services

// Real response shape from api.fxtwitter.com for a public tweet.
let fxJSON = """
{"code":200,"message":"OK","tweet":{"url":"https://x.com/TheEllenShow/status/440322224407314432","id":"440322224407314432",
"media":{"all":[{"type":"photo","id":"440322224092745728","url":"https://pbs.twimg.com/media/BhxWutnCEAAtEQ6.jpg?name=orig","width":1920,"height":1080}],
"photos":[{"type":"photo","id":"440322224092745728","url":"https://pbs.twimg.com/media/BhxWutnCEAAtEQ6.jpg?name=orig","width":1920,"height":1080}]}}}
"""
let fx = TweetLookup.wallpapers(fromFx: Data(fxJSON.utf8), statusID: "440322224407314432", addedAt: start)
check(fx.count == 1 && fx.first?.id == "BhxWutnCEAAtEQ6" && fx.first?.width == 1920, "fxtwitter photo read")
check(fx.first?.sources == [.link], "pasted photos are marked as links")
check(TweetLookup.wallpapers(fromFx: Data(#"{"code":404,"message":"NOT_FOUND"}"#.utf8), statusID: "1", addedAt: start).isEmpty, "missing tweet gives nothing")

let syndicationJSON = """
{"__typename":"Tweet","id_str":"440322224407314432","user":{"screen_name":"TheEllenShow"},
"mediaDetails":[{"type":"photo","media_url_https":"https://pbs.twimg.com/media/BhxWutnCEAAtEQ6.jpg","original_info":{"height":1080,"width":1920,"focus_rects":[]}},
{"type":"video","media_url_https":"https://pbs.twimg.com/ext_tw_video_thumb/1/pu/img/v.jpg"}]}
"""
let syndication = TweetLookup.wallpapers(fromSyndication: Data(syndicationJSON.utf8), statusID: "440322224407314432", addedAt: start)
check(syndication.count == 1 && syndication.first?.height == 1080, "syndication photo read, video skipped")
check(syndication.first?.tweetURL?.absoluteString == "https://x.com/TheEllenShow/status/440322224407314432", "syndication tweet link")
// The value X's own embed script computes for this tweet; the last digits depend on float rounding.
check(TweetLookup.syndicationToken(statusID: "440322224407314432").hasPrefix("12fb9qdo78a"), "syndication token")

// MARK: - Library

var library = Library()
check(library.add(harvested, reviveDeleted: false).count == 2, "both photos added")
check(library.add(harvested, reviveDeleted: false).isEmpty, "importing again adds nothing")
let sameAsLike = Wallpaper(photoURL: "https://pbs.twimg.com/media/HV8fJNdaYAA4Y2D?format=jpg&name=orig", tweetURL: nil,
                           width: 1981, height: 1981, source: .likes, addedAt: start)!
library.add([sameAsLike], reviveDeleted: false)
check(library.wallpapers.count == 2 && library.wallpaper("HV8fJNdaYAA4Y2D")?.sources == [.bookmarks, .likes],
      "same photo in likes merges into one with both sources")
check(library.count(of: .likes) == 1 && library.count(of: .bookmarks) == 2, "counts per source")

library.remove(["HV8fJNra0AAo106"])
check(library.wallpapers.count == 1 && library.deletedIDs.contains("HV8fJNra0AAo106"), "delete remembers the photo")
check(library.add(harvested, reviveDeleted: false).isEmpty, "deleted photo stays deleted on the next import")
check(library.add(harvested, reviveDeleted: true) == ["HV8fJNra0AAo106"], "pasting its link brings it back")
check(!library.deletedIDs.contains("HV8fJNra0AAo106"), "and forgets the deletion")

library.update("HV8fJNdaYAA4Y2D") { $0.isDownloaded = true }
check(library.pendingCount == 1, "one download still pending")
library.update("HV8fJNra0AAo106") { $0.failed = true }
check(library.pendingCount == 0 && library.failedCount == 1, "failed download counted apart")

let newer = Wallpaper(photoURL: "https://pbs.twimg.com/media/NEWER.png", tweetURL: nil, width: 1, height: 2,
                      source: .link, addedAt: start.addingTimeInterval(60))!
library.add([newer], reviveDeleted: true)
check(library.wallpapers.first?.id == "NEWER" && library.wallpapers.first?.fileExtension == "png", "newest addition shows first")

let encoded = try! JSONEncoder().encode(library)
let decoded = try! JSONDecoder().decode(Library.self, from: encoded)
check(decoded == library, "library survives saving and loading")

print("\(checks - failures)/\(checks) checks passed")
if failures > 0 { exit(1) }
