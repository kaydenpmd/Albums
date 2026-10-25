import SwiftUI

/// Square album artwork with Apple Music's rounded corners, hairline edge, and music-note placeholder.
struct ArtworkView: View {
    let album: Album
    /// Pixel size to decode at; pick roughly the displayed size × screen scale.
    var pixelSize: Int = 600
    var cornerRadius: CGFloat = 7
    /// The faint edge that keeps white covers from melting into a white page.
    /// Off for edge-to-edge artwork, which has no edge to draw.
    var showsHairline = true

    @State private var loadedImage: UIImage?

    var body: some View {
        let image = loadedImage ?? ArtworkLoader.shared.cachedImage(for: album, pixelSize: pixelSize)

        Rectangle()
            .fill(Color(.secondarySystemFill))
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    GeometryReader { proxy in
                        Image(systemName: "music.note")
                            .font(.system(size: proxy.size.width * 0.3))
                            .foregroundStyle(.tertiary)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                if showsHairline {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
            }
            .task(id: album.artworkURL) {
                if let image = await ArtworkLoader.shared.image(for: album, pixelSize: pixelSize) {
                    loadedImage = image
                }
            }
            .accessibilityHidden(true)
    }
}
