import Foundation
import Observation

/// The saved library. Backed by a JSON file in the App Group container that the app and the
/// share extension both write to, so every change is a coordinated read-modify-write of the
/// file rather than an overwrite from memory.
@MainActor
@Observable
final class AlbumStore {
    enum AddOutcome {
        case added(Album)
        case alreadySaved(Album)
    }

    private(set) var albums: [Album] = []

    private let fileURL: URL
    private var isResolvingPending = false

    init(fileURL: URL = AlbumStore.defaultFileURL) {
        self.fileURL = fileURL
        reload()
    }

    nonisolated static var defaultFileURL: URL {
        AppGroup.containerURL.appending(path: "Library.json")
    }

    /// Picks up changes made by the other process (e.g. albums saved from the share sheet).
    func reload() {
        let loaded = LibraryFile.read(at: fileURL)
        if loaded != albums {
            albums = loaded
        }
    }

    func album(withID id: Album.ID) -> Album? {
        albums.first { $0.id == id }
    }

    /// Saves `album`, unless it's already saved. Saving the details of an album
    /// that is still waiting for them (see `Album.pending(for:)`) fills them in,
    /// and so does saving the album of a song that is waiting as "song-<id>".
    @discardableResult
    func add(_ album: Album) -> AddOutcome {
        var outcome = AddOutcome.added(album)
        mutate { list in
            if let index = list.firstIndex(where: { $0.id == album.id }) {
                if list[index].isPending, !album.isPending {
                    list[index] = list[index].updatingDetails(from: album)
                    outcome = .added(list[index])
                } else {
                    outcome = .alreadySaved(list[index])
                }
            } else {
                list.append(album)
            }
            // A song waiting as "song-<id>" whose album this is: the album
            // stands in for it now.
            guard !album.isPending else { return }
            let songIDs = Set(album.tracks.map { "song-\($0.id)" })
            list.removeAll { $0.isPending && songIDs.contains($0.id) }
        }
        return outcome
    }

    func delete(_ album: Album) {
        mutate { list in list.removeAll { $0.id == album.id } }
        ArtworkLoader.removeArtwork(for: album.id)
    }

    func setListened(_ listened: Bool, for album: Album) {
        mutate { list in
            guard let index = list.firstIndex(where: { $0.id == album.id }) else { return }
            list[index].listenedAt = listened ? (list[index].listenedAt ?? .now) : nil
        }
    }

    /// Fetches details for albums the share extension saved while offline.
    func resolvePendingAlbums(using service: AlbumMetadataService = AlbumMetadataService()) async {
        guard !isResolvingPending else { return }
        isResolvingPending = true
        defer { isResolvingPending = false }

        for pending in albums where pending.isPending {
            guard let link = AppleMusicLink(url: pending.url),
                  let fetched = try? await service.fetchAlbum(for: link)
            else { continue }
            mutate { list in
                guard let index = list.firstIndex(where: { $0.id == pending.id }) else { return }
                if fetched.id != pending.id, list.contains(where: { $0.id == fetched.id }) {
                    // A song link that turned out to be an album that's already saved.
                    list.remove(at: index)
                } else {
                    list[index] = list[index].updatingDetails(from: fetched)
                }
            }
        }
    }

    private func mutate(_ change: @escaping (inout [Album]) -> Void) {
        albums = LibraryFile.update(at: fileURL, change)
    }
}

// MARK: - File access

/// Reads and writes `Library.json` under `NSFileCoordinator`, which serializes access between
/// the app and the share extension.
enum LibraryFile {
    private struct Contents: Codable {
        var version = 1
        var albums: [Album]
    }

    /// Decodes each album on its own, so one bad entry can't take the whole library with it.
    private struct LossyContents: Decodable {
        var albums: [Album]

        private struct LossyAlbum: Decodable {
            let album: Album?
            init(from decoder: Decoder) throws {
                album = try? decoder.singleValueContainer().decode(Album.self)
            }
        }

        private enum CodingKeys: String, CodingKey { case albums }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            albums = try container.decode([LossyAlbum].self, forKey: .albums).compactMap(\.album)
        }
    }

    static func read(at url: URL) -> [Album] {
        var result: [Album] = []
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            result = decode(at: readURL)
        }
        if coordinationError != nil {
            result = decode(at: url)
        }
        return result
    }

    static func update(at url: URL, _ change: @escaping (inout [Album]) -> Void) -> [Album] {
        var result: [Album] = []
        var didRun = false
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { writeURL in
            var albums = decode(at: writeURL)
            change(&albums)
            write(albums, to: writeURL)
            result = albums
            didRun = true
        }
        if !didRun {
            var albums = decode(at: url)
            change(&albums)
            write(albums, to: url)
            result = albums
        }
        return result
    }

    private static func decode(at url: URL) -> [Album] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }
        do {
            return try JSONDecoder().decode(LossyContents.self, from: data).albums
        } catch {
            // Never silently overwrite a library we can't read: set it aside first.
            let backup = url.deletingLastPathComponent()
                .appending(path: "Library-unreadable-\(Int(Date.now.timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            return []
        }
    }

    private static func write(_ albums: [Album], to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Contents(albums: albums))
            try data.write(to: url, options: .atomic)
        } catch {
            assertionFailure("Couldn't save library: \(error)")
        }
    }
}
