import ImageIO
import UIKit

/// Loads album artwork: memory cache → file in the shared container → Apple's image CDN.
///
/// Artwork fetched by the share extension is written to the shared container, so the app can
/// show it right away (and offline).
@MainActor
final class ArtworkLoader {
    static let shared = ArtworkLoader()

    /// Pixel size of the artwork kept on disk; views downsample from it. Sized
    /// for the largest place a cover appears, the share sheet's 220 pt card,
    /// on a 3× screen.
    nonisolated static let storedPixelSize = 700

    private let memory = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        memory.totalCostLimit = 64 * 1024 * 1024
    }

    /// Synchronous memory-cache hit, so cells scrolling back into view don't flash a placeholder.
    func cachedImage(for album: Album, pixelSize: Int) -> UIImage? {
        memory.object(forKey: Self.cacheKey(album.id, pixelSize) as NSString)
    }

    func image(for album: Album, pixelSize: Int) async -> UIImage? {
        let key = Self.cacheKey(album.id, pixelSize)
        if let image = memory.object(forKey: key as NSString) { return image }
        if let task = inFlight[key] { return await task.value }

        let task = Task.detached(priority: .userInitiated) {
            await Self.loadImage(for: album, pixelSize: pixelSize)
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image {
            memory.setObject(image, forKey: key as NSString, cost: pixelSize * pixelSize * 4)
        }
        return image
    }

    nonisolated static func removeArtwork(for albumID: Album.ID) {
        try? FileManager.default.removeItem(at: fileURL(for: albumID))
    }

    // MARK: - Loading

    private nonisolated static func loadImage(for album: Album, pixelSize: Int) async -> UIImage? {
        guard let file = await localFile(for: album) else { return nil }
        if let image = downsample(file, maxPixelSize: pixelSize) {
            return image
        }
        // Unreadable file: remove it so the next attempt downloads a fresh copy.
        try? FileManager.default.removeItem(at: file)
        return nil
    }

    private nonisolated static func localFile(for album: Album) async -> URL? {
        let file = fileURL(for: album.id)
        if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
            return file
        }
        guard let remote = album.artworkURL(pixelSize: storedPixelSize) else { return nil }
        do {
            // Bounded, because the share sheet waits on this before closing.
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: remote, timeoutInterval: 10))
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetCount(source) > 0
            else { return nil }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            return file
        } catch {
            return nil
        }
    }

    /// Decodes the image at no more than `maxPixelSize` on its longest side, which keeps memory
    /// use low compared with decoding the full file and letting SwiftUI scale it down.
    private nonisolated static func downsample(_ url: URL, maxPixelSize: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return UIImage(cgImage: image)
    }

    private nonisolated static func fileURL(for albumID: Album.ID) -> URL {
        let safeName = String(albumID.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" })
        // The size is in the name so that changing storedPixelSize fetches
        // covers again instead of reusing smaller ones.
        return AppGroup.containerURL
            .appending(path: "Artwork", directoryHint: .isDirectory)
            .appending(path: "\(safeName)-\(storedPixelSize).jpg")
    }

    private nonisolated static func cacheKey(_ albumID: Album.ID, _ pixelSize: Int) -> String {
        "\(albumID)@\(pixelSize)"
    }
}
