import Foundation

/// The library's sort order, offered from the "…" menu as Apple Music offers its own.
enum LibrarySort: String, CaseIterable, Identifiable {
    case recentlyAdded
    case title
    case artist
    case releaseDate

    var id: Self { self }

    var label: String {
        switch self {
        case .recentlyAdded: "Recently Added"
        case .title: "Title"
        case .artist: "Artist"
        case .releaseDate: "Release Date"
        }
    }

    func sorted(_ albums: [Album]) -> [Album] {
        switch self {
        case .recentlyAdded:
            return albums.sorted { $0.addedAt > $1.addedAt }
        case .title:
            return albums.sorted { Self.ascending($0.title, $1.title, then: $0.artist, $1.artist) }
        case .artist:
            return albums.sorted { Self.ascending($0.artist, $1.artist, then: $0.title, $1.title) }
        case .releaseDate:
            return albums.sorted { ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast) }
        }
    }

    private static func ascending(_ a: String, _ b: String, then c: String, _ d: String) -> Bool {
        let primary = a.localizedStandardCompare(b)
        if primary == .orderedSame {
            return c.localizedStandardCompare(d) == .orderedAscending
        }
        return primary == .orderedAscending
    }
}

/// Which albums the grid shows, from the filter button, the way Apple Music's
/// filter offers All Albums, Favorites and Downloaded.
enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case notListened
    case listened

    var id: Self { self }

    var label: String {
        switch self {
        case .all: "All Albums"
        case .notListened: "Not Listened"
        case .listened: "Listened"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.stack"
        case .notListened: "circle"
        case .listened: "checkmark.circle"
        }
    }

    func includes(_ album: Album) -> Bool {
        switch self {
        case .all: true
        case .notListened: !album.isListened
        case .listened: album.isListened
        }
    }
}
