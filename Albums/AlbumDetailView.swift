import SwiftUI
import UIKit

/// An album's page, laid out like Apple Music's: the artwork as a plain square,
/// on a page colored from the artwork, then the title block, a Play capsule
/// between two round buttons, the tracks, and the release details. Play opens
/// the album in Apple Music.
///
/// The artwork is shown whole and untouched, never faded or cropped into the
/// page (the owner's call, 25 Oct 2026, after trying iOS 27's edge-to-edge
/// version; it also keeps to Apple's rule against altering album art).
///
/// Measured from Apple's iOS 26.4 screenshots on a 402 pt iPhone: artwork 77%
/// of the width, title 22 pt bold, artist 20 pt, details 12 pt semibold;
/// buttons 47 pt tall and 14 pt apart; track rows 50 pt.
struct AlbumDetailView: View {
    let albumID: Album.ID

    @Environment(AlbumStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var albumPendingDeletion: Album?
    @State private var isTitleInBar = false
    /// The album as last shown, kept so the page doesn't blank out while it
    /// slides away after a delete.
    @State private var lastShown: Album?
    @State private var pageColor: UIColor?
    /// Where the header's title ends, in the page's own coordinates, measured
    /// so a title that wraps to two or three lines is accounted for.
    @State private var headerTitleBottom: CGFloat = .infinity

    var body: some View {
        let current = store.album(withID: albumID)
        Group {
            if let album = current ?? lastShown {
                page(album)
            } else {
                ContentUnavailableView("Album Removed", systemImage: "square.stack")
            }
        }
        .onChange(of: current, initial: true) { _, album in
            if let album { lastShown = album }
        }
    }

    /// The page's background, and whether light or dark text reads on it. With
    /// Increase Contrast on, Music keeps the system background, and so does this.
    private var palette: (background: Color, scheme: ColorScheme) {
        guard let pageColor, contrast != .increased else {
            return (Color(.systemBackground), systemScheme)
        }
        return (Color(uiColor: pageColor), pageColor.isLight ? .light : .dark)
    }

    private func page(_ album: Album) -> some View {
        let palette = palette
        let titleBottom = headerTitleBottom
        return ScrollView {
            VStack(spacing: 0) {
                header(album, background: palette.background)
                if !album.tracks.isEmpty {
                    TrackList(album: album)
                        .padding(.top, 20)
                }
                footer(album)
            }
            .coordinateSpace(.named(Self.pageSpace))
        }
        .background(palette.background)
        .animation(.easeInOut(duration: 0.3), value: pageColor)
        // The title moves into the bar once the header's own title has
        // scrolled up under it.
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > titleBottom
        } action: { _, isPastHeader in
            withAnimation(.easeInOut(duration: 0.2)) { isTitleInBar = isPastHeader }
        }
        .navigationTitle(isTitleInBar ? album.displayTitle : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    AlbumMenuItems(album: album, store: store) {
                        albumPendingDeletion = album
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
        .confirmDeletion(of: $albumPendingDeletion, in: store) {
            dismiss()
        }
        .task(id: album.artworkURL) {
            pageColor = await ArtworkLoader.shared.pageColor(for: album)
        }
        // Everything on the page reads against the page color. iOS 26's glass
        // bars adapt to the content under them on their own.
        .environment(\.colorScheme, palette.scheme)
    }

    // MARK: - Header

    /// nonisolated because the geometry closures that use it may run off the main actor.
    private nonisolated static let pageSpace = "albumPage"

    /// 77% of the width (309 pt on a 402 pt iPhone), capped for iPad.
    private nonisolated static func artworkSize(forWidth width: CGFloat) -> CGFloat {
        min(width * 0.77, 400)
    }

    @ViewBuilder
    private func header(_ album: Album, background: Color) -> some View {
        VStack(spacing: 0) {
            ArtworkView(album: album, pixelSize: ArtworkLoader.storedPixelSize, cornerRadius: 10)
                .containerRelativeFrame(.horizontal) { width, _ in
                    Self.artworkSize(forWidth: width)
                }
                .padding(.top, 8)

            Text(album.displayTitle)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .named(Self.pageSpace)).maxY
                } action: { bottom in
                    headerTitleBottom = bottom
                }
                .padding(.top, 30)

            Text(album.displayArtist)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
                .padding(.horizontal, 20)

            if let details = detailsLine(album) {
                Text(details)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            HStack(spacing: 14) {
                ShareLink(item: album.url) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(RoundButtonStyle(pageBackground: background))
                .accessibilityLabel("Share")

                Button {
                    openURL(album.url)
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(PlayButtonStyle(pageBackground: background))

                Button {
                    withAnimation { store.setListened(!album.isListened, for: album) }
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(RoundButtonStyle(pageBackground: background, isOn: album.isListened))
                .accessibilityLabel("Listened")
                .accessibilityValue(album.isListened ? "Yes" : "No")
            }
            .padding(.top, 16)
        }
    }

    /// "Rock · 2005".
    private func detailsLine(_ album: Album) -> String? {
        var parts: [String] = []
        if let genre = album.genre { parts.append(genre) }
        if let year = album.releaseYear { parts.append(String(year)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Footer

    private func footer(_ album: Album) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let releaseDate = album.releaseDate {
                // UTC, because Apple's release dates are midnight-ish UTC and
                // would otherwise show as the day before west of Greenwich.
                Text(releaseDate.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: .gmt)))
            }
            if let summary = songSummary(album) {
                Text(summary)
            }
            if let copyright = album.copyright {
                Text(copyright)
            }
            Text("Added \(album.addedAt.formatted(date: .abbreviated, time: .omitted))")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 40)
    }

    /// "15 songs, 40 minutes".
    private func songSummary(_ album: Album) -> String? {
        let count = album.tracks.isEmpty ? (album.trackCount ?? 0) : album.tracks.count
        guard count > 0 else { return nil }
        let songs = count == 1 ? "1 song" : "\(count) songs"
        guard let duration = album.totalDuration else { return songs }
        return "\(songs), \(duration.formatted(.units(allowed: [.hours, .minutes], width: .wide)))"
    }
}

// MARK: - Buttons

/// The Play capsule: filled with the text color, labeled in the page color.
private struct PlayButtonStyle: ButtonStyle {
    let pageBackground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(pageBackground)
            .frame(width: 160, height: 47)
            .background(Color.primary, in: .capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(.capsule)
    }
}

/// The round buttons either side of Play: a faint fill, or a solid one when on.
private struct RoundButtonStyle: ButtonStyle {
    let pageBackground: Color
    var isOn = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(isOn ? pageBackground : Color.primary)
            .frame(width: 47, height: 47)
            .background(isOn ? Color.primary : Color.primary.opacity(0.1), in: .circle)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(.circle)
    }
}

// MARK: - Tracks

/// Rows 50 pt tall. The number sits 6 pt in from the margin and the title
/// 28.5 pt in; separators start under the title, except the first and last,
/// which run margin to margin.
private struct TrackList: View {
    let album: Album

    private struct Disc: Identifiable {
        let number: Int
        let tracks: [Track]
        var id: Int { number }
    }

    private var discs: [Disc] {
        Dictionary(grouping: album.tracks, by: \.disc)
            .map { Disc(number: $0.key, tracks: $0.value) }
            .sorted { $0.number < $1.number }
    }

    var body: some View {
        let allDiscs = discs
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(allDiscs) { disc in
                if allDiscs.count > 1 {
                    Text("Disc \(disc.number)")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.top, disc.number == allDiscs.first?.number ? 0 : 24)
                        .padding(.bottom, 8)
                }
                Divider()
                    .padding(.horizontal, 20)
                ForEach(disc.tracks) { track in
                    TrackRow(album: album, track: track)
                    if track.id == disc.tracks.last?.id {
                        Divider()
                            .padding(.horizontal, 20)
                    } else {
                        Divider()
                            .padding(.leading, 20 + TrackRow.titleInset)
                            .padding(.trailing, 20)
                    }
                }
            }
        }
    }
}

private struct TrackRow: View {
    let album: Album
    let track: Track

    static let numberInset: CGFloat = 6
    static let titleInset: CGFloat = 28.5

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 0) {
            Button {
                openURL(album.url(for: track))
            } label: {
                HStack(spacing: 0) {
                    Text(track.number > 0 ? String(track.number) : "")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.leading, Self.numberInset)
                        .frame(width: Self.titleInset, alignment: .leading)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(track.title)
                                .lineLimit(1)
                            if track.isExplicit {
                                ExplicitBadge()
                            }
                        }
                        // Features and compilations: show who's on this track
                        // when it isn't simply the album artist.
                        if !track.artist.isEmpty, track.artist != album.artist {
                            Text(track.artist)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                }
                .padding(.vertical, 6)
                .frame(minHeight: 49.5)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    openURL(album.url(for: track))
                } label: {
                    Label("Open in Apple Music", systemImage: "arrow.up.forward.app")
                }
                ShareLink(item: album.url(for: track)) {
                    Label("Share Song…", systemImage: "square.and.arrow.up")
                }
                Button {
                    UIPasteboard.general.url = album.url(for: track)
                } label: {
                    Label("Copy Link", systemImage: "link")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("More for \(track.title)")
        }
        .padding(.leading, 20)
        .padding(.trailing, 10)
    }
}

private extension UIColor {
    /// Whether dark text reads better than white on this color.
    var isLight: Bool {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return false }
        return 0.299 * red + 0.587 * green + 0.114 * blue > 0.62
    }
}
