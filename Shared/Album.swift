import Foundation

/// A saved Apple Music album.
///
/// Albums are identified by their Apple Music catalog ID, so saving the same album twice
/// (even from a song link) is detected as a duplicate.
struct Album: Identifiable, Codable, Hashable, Sendable {
    /// Apple Music catalog ID (e.g. "1440857781"). Pending albums saved from a song link
    /// while offline use "song-<songID>" until their details are fetched.
    var id: String
    var title: String
    var artist: String
    /// Canonical Apple Music link for the album.
    var url: URL
    var artworkURL: URL?
    var releaseDate: Date?
    var genre: String?
    var trackCount: Int?
    var isExplicit: Bool
    var copyright: String?
    var tracks: [Track]
    var addedAt: Date
    /// When the album was marked as listened. `nil` means it's still waiting to be heard.
    var listenedAt: Date?

    init(
        id: String,
        title: String,
        artist: String,
        url: URL,
        artworkURL: URL? = nil,
        releaseDate: Date? = nil,
        genre: String? = nil,
        trackCount: Int? = nil,
        isExplicit: Bool = false,
        copyright: String? = nil,
        tracks: [Track] = [],
        addedAt: Date = .now,
        listenedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.url = url
        self.artworkURL = artworkURL
        self.releaseDate = releaseDate
        self.genre = genre
        self.trackCount = trackCount
        self.isExplicit = isExplicit
        self.copyright = copyright
        self.tracks = tracks
        self.addedAt = addedAt
        self.listenedAt = listenedAt
    }

    /// An album saved without its details (the share extension was offline). The app fills
    /// it in the next time it can reach Apple Music.
    static func pending(for link: AppleMusicLink) -> Album {
        let id: String
        switch link.target {
        case .album(let albumID): id = albumID
        case .song(let songID): id = "song-\(songID)"
        case .unsupported(let kind): id = "\(kind)-\(UUID().uuidString)"
        }
        return Album(id: id, title: "", artist: "", url: link.url)
    }

    // Lenient decoding, so a library written by an older or newer version of the app still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        url = try c.decode(URL.self, forKey: .url)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        artist = try c.decodeIfPresent(String.self, forKey: .artist) ?? ""
        artworkURL = try? c.decodeIfPresent(URL.self, forKey: .artworkURL)
        releaseDate = try? c.decodeIfPresent(Date.self, forKey: .releaseDate)
        genre = try? c.decodeIfPresent(String.self, forKey: .genre)
        trackCount = try? c.decodeIfPresent(Int.self, forKey: .trackCount)
        isExplicit = (try? c.decodeIfPresent(Bool.self, forKey: .isExplicit)) ?? false
        copyright = try? c.decodeIfPresent(String.self, forKey: .copyright)
        tracks = (try? c.decodeIfPresent([Track].self, forKey: .tracks)) ?? []
        addedAt = (try? c.decodeIfPresent(Date.self, forKey: .addedAt)) ?? .now
        listenedAt = try? c.decodeIfPresent(Date.self, forKey: .listenedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, artist, url, artworkURL, releaseDate, genre, trackCount
        case isExplicit, copyright, tracks, addedAt, listenedAt
    }
}

struct Track: Identifiable, Codable, Hashable, Sendable {
    /// Apple Music catalog ID of the song.
    var id: String
    var title: String
    var artist: String
    var number: Int
    var disc: Int
    var durationMillis: Int?
    var isExplicit: Bool
}

// MARK: - Derived values

extension Album {
    /// True while the album is still waiting for its details (see `pending(for:)`).
    var isPending: Bool { title.isEmpty }

    var isListened: Bool { listenedAt != nil }

    var displayTitle: String { isPending ? "Fetching Details…" : title }

    var displayArtist: String { isPending ? "Apple Music" : artist }

    /// Release year, read in UTC because Apple stores release dates as midnight-ish UTC timestamps.
    var releaseYear: Int? {
        guard let releaseDate else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.component(.year, from: releaseDate)
    }

    var totalDuration: Duration? {
        let millis = tracks.compactMap(\.durationMillis).reduce(0, +)
        return millis > 0 ? .milliseconds(millis) : nil
    }

    /// Apple Music link that opens the album at a specific song.
    func url(for track: Track) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.queryItems = [URLQueryItem(name: "i", value: track.id)]
        return components.url ?? url
    }

    /// Artwork URL at a given square pixel size. Apple's image CDN renders any size on request
    /// when the last path component is rewritten, e.g. `…/100x100bb.jpg` → `…/600x600bb.jpg`.
    func artworkURL(pixelSize: Int) -> URL? {
        guard let artworkURL else { return nil }
        guard artworkURL.host()?.hasSuffix("mzstatic.com") == true,
              artworkURL.path().contains("/image/thumb/")
        else { return artworkURL }
        let resized = artworkURL
            .deletingLastPathComponent()
            .appending(path: "\(pixelSize)x\(pixelSize)bb.jpg")
        var components = URLComponents(url: resized, resolvingAgainstBaseURL: false)
        components?.query = nil
        return components?.url ?? resized
    }

    /// Fills in fetched details while keeping what belongs to the user (when it was saved and listened to).
    func updatingDetails(from fetched: Album) -> Album {
        var updated = fetched
        updated.addedAt = addedAt
        updated.listenedAt = listenedAt
        return updated
    }
}
