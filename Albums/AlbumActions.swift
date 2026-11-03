import SwiftUI

/// The card above the long-press menu, like Music's: the cover, then the title
/// over the artist, and a ">" because tapping the card opens the album (see
/// `AlbumGridItem`). Measured from the owner's iOS 26 screenshot on a 375 pt
/// iPhone: a 300 pt card; a 92 pt cover inset 16 pt, its 16 pt corners
/// concentric with the card's 32 pt ones; a 16 pt gap to the text; a 17 pt
/// semibold title over a 15 pt artist; a regular-weight chevron 12 pt from the
/// edge.
struct AlbumMenuPreview: View {
    static let width: CGFloat = 300

    let album: Album

    var body: some View {
        // No stack spacing: it would also go either side of the Spacer and
        // squeeze the title onto two lines. The gaps are padding instead.
        HStack(spacing: 0) {
            // 600 px is the grid's size, already in memory, so the card
            // appears with its cover rather than a placeholder.
            ArtworkView(album: album, pixelSize: 600, cornerRadius: 16)
                .frame(width: 92, height: 92)
                .padding(.trailing, 16)

            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.headline)
                    .lineLimit(2)

                Text(album.displayArtist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.forward")
                .font(.body)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 16)
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(width: Self.width)
        .background(Color(.secondarySystemGroupedBackground))
    }

    /// The title, with the explicit "E" after it when there is one, flowing
    /// with the text if the title wraps.
    private var title: Text {
        guard album.isExplicit else { return Text(album.displayTitle) }
        let badge = Text(Image(systemName: "e.square.fill")).foregroundStyle(.secondary)
        return Text("\(album.displayTitle) \(badge)")
    }
}

extension View {
    /// Asks before deleting, as Apple Music does. `album` is the one waiting
    /// for an answer; setting it presents the question.
    func confirmDeletion(of album: Binding<Album?>, in store: AlbumStore) -> some View {
        modifier(ConfirmDeletion(album: album, store: store))
    }
}

private struct ConfirmDeletion: ViewModifier {
    @Binding var album: Album?
    let store: AlbumStore

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Delete this album from your library?",
            isPresented: Binding(get: { album != nil }, set: { if !$0 { album = nil } }),
            titleVisibility: .visible,
            presenting: album
        ) { album in
            Button("Delete Album", role: .destructive) {
                withAnimation { store.delete(album) }
            }
        } message: { album in
            Text("\u{201C}\(album.displayTitle)\u{201D} will be removed from Albums. It stays in Apple Music.")
        }
    }
}
