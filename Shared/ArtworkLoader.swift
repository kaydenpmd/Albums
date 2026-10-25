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
    /// for the album page's edge-to-edge artwork: 402 pt × 3 on an iPhone 17.
    nonisolated static let storedPixelSize = 1200

    private let memory = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private var pageColors: [Album.ID: UIColor] = [:]

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

    /// The color along the bottom edge of the artwork, which the album page
    /// fades the artwork into and uses as its background. nil until the
    /// artwork is available.
    func pageColor(for album: Album) async -> UIColor? {
        if let color = pageColors[album.id] { return color }
        guard let image = await image(for: album, pixelSize: 600) else { return nil }
        let color = await Task.detached(priority: .userInitiated) {
            Self.bottomEdgeColor(of: image)
        }.value
        if let color { pageColors[album.id] = color }
        return color
    }

    /// Makes sure the album's artwork is saved to disk.
    nonisolated static func prefetch(_ album: Album) async {
        _ = await localFile(for: album)
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

    /// Averages the bottom fifth of the image, drawn small: a 16 × 16 bitmap
    /// is plenty for one color, and drawing it down does most of the averaging.
    private nonisolated static func bottomEdgeColor(of image: UIImage) -> UIColor? {
        guard let cgImage = image.cgImage else { return nil }
        let size = 16
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let data = context.data else { return nil }

        let bytesPerRow = context.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * size)
        var red = 0, green = 0, blue = 0, count = 0
        // Rows run top to bottom in the bitmap's memory, so the last rows are the bottom edge.
        for row in (size - size / 5)..<size {
            for column in 0..<size {
                let offset = row * bytesPerRow + column * 4
                red += Int(pixels[offset])
                green += Int(pixels[offset + 1])
                blue += Int(pixels[offset + 2])
                count += 1
            }
        }
        let scale = CGFloat(count * 255)
        return UIColor(red: CGFloat(red) / scale, green: CGFloat(green) / scale, blue: CGFloat(blue) / scale, alpha: 1)
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
