import SwiftUI

/// What the share sheet shows: a spinner while the album is looked up, then the
/// album itself with a check, then it closes on its own.
struct ShareView: View {
    let model: ShareModel

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
                .animation(.snappy, value: model.phase)
                .navigationTitle("Albums")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if model.phase == .looking {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { model.cancel() }
                        }
                    } else {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { model.done() }
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .looking:
            ProgressView("Finding Album…")
                .controlSize(.large)
        case .saved(let album):
            SavedAlbumCard(album: album, status: "Added to Albums", symbol: "checkmark.circle.fill")
        case .alreadySaved(let album):
            SavedAlbumCard(album: album, status: "Already in Albums", symbol: "checkmark.circle")
        case .savedForLater:
            ContentUnavailableView {
                Label("Saved for Later", systemImage: "clock.arrow.circlepath")
            } description: {
                Text("Apple Music couldn't be reached, so the album's details will fill in the next time you open Albums.")
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't Save", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
        }
    }
}

private struct SavedAlbumCard: View {
    let album: Album
    let status: String
    let symbol: String

    var body: some View {
        VStack(spacing: 0) {
            ArtworkView(album: album, pixelSize: 600, cornerRadius: 10)
                .frame(width: 220)
                .shadow(color: .black.opacity(0.18), radius: 16, y: 8)

            Text(album.displayTitle)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, 20)

            Text(album.displayArtist)
                .font(.title3)
                .foregroundStyle(.tint)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .padding(.top, 2)

            Label(status, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(.secondary)
                .symbolEffect(.bounce, options: .nonRepeating)
                .padding(.top, 24)
        }
        .transition(.scale(scale: 0.92).combined(with: .opacity))
    }
}
