import Foundation

/// A parsed Apple Music link, e.g.
/// - `https://music.apple.com/us/album/in-between-dreams/1440857781`
/// - `https://music.apple.com/us/album/better-together/1440857781?i=1440857786` (a song on an album)
/// - `https://music.apple.com/gb/song/better-together/1440857786`
/// - `https://itunes.apple.com/us/album/in-between-dreams/id1440857781` (legacy)
struct AppleMusicLink: Hashable, Sendable {
    enum Target: Hashable, Sendable {
        case album(id: String)
        case song(id: String)
        /// An Apple Music link to something other than an album or song (playlist, artist, station…).
        case unsupported(kind: String)
    }

    let target: Target
    /// Two-letter storefront (country) code from the link, used for catalog lookups.
    let storefront: String
    let url: URL

    /// Returns `nil` when the URL isn't an Apple Music link at all.
    init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host()?.lowercased(), Self.isAppleMusicHost(host)
        else { return nil }

        var parts = url.pathComponents.filter { $0 != "/" }
        var storefront = "us"
        if let first = parts.first, first.count == 2, first.allSatisfy(\.isLetter) {
            storefront = first.lowercased()
            parts.removeFirst()
        }
        guard let kind = parts.first?.lowercased() else { return nil }

        let lastID = parts.count >= 2 ? Self.catalogID(from: parts[parts.count - 1]) : nil
        switch (kind, lastID) {
        case ("album", let id?):
            target = .album(id: id)
        case ("song", let id?):
            target = .song(id: id)
        default:
            target = .unsupported(kind: kind)
        }
        self.storefront = storefront
        self.url = url
    }

    /// Finds the first Apple Music link in some text, such as "Listen on Apple Music: https://…".
    static func first(in text: String) -> AppleMusicLink? {
        urls(in: text).lazy.compactMap(AppleMusicLink.init(url:)).first
    }

    /// All web links in a piece of text.
    static func urls(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, options: [], range: range).compactMap(\.url)
    }

    private static func isAppleMusicHost(_ host: String) -> Bool {
        ["music.apple.com", "itunes.apple.com"].contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// "1440857781" or legacy "id1440857781" → "1440857781".
    private static func catalogID(from component: String) -> String? {
        let digits = component.hasPrefix("id") ? String(component.dropFirst(2)) : component
        guard !digits.isEmpty, digits.allSatisfy(\.isASCIIDigit) else { return nil }
        return digits
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
