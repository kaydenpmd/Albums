import Foundation
import os

/// Looks up an album's details from Apple's public catalog.
///
/// The same exact lookup Ammy and Issun make for cover art: iTunes Lookup by
/// catalog ID, never a search by name, so it can't pick the wrong album. Either
/// the ID resolves or it doesn't. No entitlement or developer token is needed,
/// and one request returns the album and its tracks (`entity=song`).
struct AlbumMetadataService: Sendable {
    enum LookupError: LocalizedError {
        case unsupportedLink(kind: String)
        /// The catalog answered, and the answer was no. Asking again won't change it.
        case notInCatalog(id: String)
        /// No usable connection. Worth saving the link and asking again later.
        case offline
        /// The catalog didn't give a usable answer (an HTTP error, a rate limit,
        /// unreadable JSON). Also worth asking again later.
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedLink(let kind) where kind == "library":
                return "That's a link to your own library. Share the album from its Apple Music page instead."
            case .unsupportedLink:
                return "Only albums and songs can be saved."
            case .notInCatalog:
                return "Apple Music doesn't have that album."
            case .offline:
                return "You're offline."
            case .failed(let why):
                return "Couldn't reach Apple Music (\(why))."
            }
        }

        /// The link is fine and the lookup just didn't happen, so a pending save will resolve later.
        var isRetryable: Bool {
            switch self {
            case .offline, .failed: return true
            case .unsupportedLink, .notInCatalog: return false
            }
        }
    }

    private static let log = Logger(subsystem: "com.local.albums", category: "lookup")

    func fetchAlbum(for link: AppleMusicLink) async throws -> Album {
        switch link.target {
        case .album(let id):
            return try await album(id: id, storefront: link.storefront)
        case .song(let songID):
            // A song link names the song, not its album: look the song up first,
            // then the album it belongs to.
            let items = try await lookup(id: songID, storefront: link.storefront) { items in
                items.contains { $0.wrapperType == "track" && $0.collectionId != nil }
            }
            guard let collectionID = items.first(where: { $0.wrapperType == "track" })?.collectionId else {
                throw LookupError.notInCatalog(id: songID)
            }
            return try await album(id: String(collectionID), storefront: link.storefront)
        case .unsupported(let kind):
            Self.log.notice("not an album or song link (\(kind, privacy: .public)): \(link.url.absoluteString, privacy: .public)")
            throw LookupError.unsupportedLink(kind: kind)
        }
    }

    // MARK: - Lookup

    private func album(id: String, storefront: String) async throws -> Album {
        let items = try await lookup(id: id, storefront: storefront) { Self.makeAlbum(from: $0) != nil }
        guard let album = Self.makeAlbum(from: items) else {
            throw LookupError.notInCatalog(id: id)
        }
        return album
    }

    /// Asks each country in turn until one answers with something `accept`s.
    ///
    /// The link's own storefront first, since an album in one country's catalog
    /// may not resolve in the lookup's default, the US. Then the device's region,
    /// then no country at all, the form Issun uses: the API refuses some region
    /// codes outright (400 for "zz", checked 24 Sept 2026), so a refusal moves on
    /// to the next country rather than ending the lookup.
    private func lookup(id: String, storefront: String, accept: ([LookupItem]) -> Bool) async throws -> [LookupItem] {
        var countries: [String?] = [storefront]
        if let region = Locale.current.region?.identifier.lowercased(), region != storefront {
            countries.append(region)
        }
        countries.append(nil)

        // A failure that might clear up outranks "not here" from the other
        // countries: the one that failed may be the only one with the album.
        var retryable: LookupError?
        for country in countries {
            do {
                let items = try await request(id: id, country: country)
                if accept(items) { return items }
                Self.log.notice("id \(id, privacy: .public) not in the catalog for country \(country ?? "(none)", privacy: .public)")
            } catch let error as LookupError {
                Self.log.error("lookup of id \(id, privacy: .public) for country \(country ?? "(none)", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                // Offline is offline in every country; don't spend three timeouts finding that out.
                if case .offline = error { throw error }
                if error.isRetryable { retryable = error }
            }
        }
        throw retryable ?? LookupError.notInCatalog(id: id)
    }

    private func request(id: String, country: String?) async throws -> [LookupItem] {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "200"),
        ]
        if let country {
            components.queryItems?.append(URLQueryItem(name: "country", value: country))
        }
        guard let url = components.url else {
            throw LookupError.failed("couldn't build the lookup URL")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10))
        } catch {
            if error.isConnectivityProblem { throw LookupError.offline }
            throw LookupError.failed(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            // 400 is the API refusing the request's parameters: a country code
            // ("zz", "419") or an ID it can't read (a 20-digit number). Asking
            // again won't change that, so it's a permanent "not here".
            if status == 400 {
                throw LookupError.notInCatalog(id: id)
            }
            throw LookupError.failed("lookup answered \(status)")
        }
        do {
            return try JSONDecoder().decode(LookupResponse.self, from: data).results
        } catch {
            throw LookupError.failed("unreadable lookup response")
        }
    }

    private static func makeAlbum(from items: [LookupItem]) -> Album? {
        guard let collection = items.first(where: { $0.wrapperType == "collection" }),
              let collectionID = collection.collectionId,
              let title = collection.collectionName,
              let viewURL = collection.collectionViewUrl.flatMap(URL.init(string:))
        else { return nil }

        // Songs only: `entity=song` also returns an album's music videos
        // (kind "music-video"), which aren't part of its track listing.
        let tracks = items
            .filter { $0.wrapperType == "track" && $0.kind == "song" && $0.collectionId == collectionID }
            .compactMap { item -> Track? in
                guard let trackID = item.trackId, let name = item.trackName else { return nil }
                return Track(
                    id: String(trackID),
                    title: name,
                    artist: item.artistName ?? "",
                    number: item.trackNumber ?? 0,
                    disc: item.discNumber ?? 1,
                    durationMillis: item.trackTimeMillis,
                    isExplicit: item.trackExplicitness == "explicit"
                )
            }
            .sorted { ($0.disc, $0.number) < ($1.disc, $1.number) }

        return Album(
            id: String(collectionID),
            title: title,
            artist: collection.artistName ?? "",
            url: withoutQuery(viewURL),
            artworkURL: collection.artworkUrl100.flatMap(URL.init(string:)),
            releaseDate: collection.releaseDate.flatMap { try? Date($0, strategy: .iso8601) },
            genre: collection.primaryGenreName,
            trackCount: collection.trackCount,
            isExplicit: collection.collectionExplicitness == "explicit",
            copyright: collection.copyright,
            tracks: tracks
        )
    }

    /// collectionViewUrl without its tracking `?uo=4`.
    private static func withoutQuery(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.query = nil
        return components.url ?? url
    }
}

// MARK: - iTunes Lookup API response

private struct LookupResponse: Decodable {
    let results: [LookupItem]
}

/// One result from the Lookup API. The album and its tracks share this shape;
/// every field is optional because each kind fills in only some of them.
private struct LookupItem: Decodable {
    let wrapperType: String?
    let kind: String?
    let collectionId: Int?
    let trackId: Int?
    let artistName: String?
    let collectionName: String?
    let trackName: String?
    let collectionViewUrl: String?
    let artworkUrl100: String?
    let releaseDate: String?
    let primaryGenreName: String?
    let trackCount: Int?
    let collectionExplicitness: String?
    let trackExplicitness: String?
    let copyright: String?
    let discNumber: Int?
    let trackNumber: Int?
    let trackTimeMillis: Int?
}
