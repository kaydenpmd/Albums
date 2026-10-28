import SwiftUI

/// What you can do with an album from the grid's long-press menu. Opening it
/// isn't here: tapping the album does that.
struct AlbumMenuItems: View {
    let album: Album
    let store: AlbumStore
    let onDelete: () -> Void

    // Music's album menu opens with a row of quick actions (Favorite, Share);
    // here the row holds Listened and Share.
    var body: some View {
        ControlGroup {
            Button {
                withAnimation { store.setListened(!album.isListened, for: album) }
            } label: {
                if album.isListened {
                    Label("Listened", systemImage: "checkmark.circle.fill")
                } else {
                    Label("Listened", systemImage: "checkmark.circle")
                }
            }
            ShareLink(item: album.url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        Section {
            Button {
                UIPasteboard.general.url = album.url
            } label: {
                Label("Copy Link", systemImage: "link")
            }
        }
        Section {
            Button(role: .destructive, action: onDelete) {
                Label("Delete from Library", systemImage: "trash")
            }
        }
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
