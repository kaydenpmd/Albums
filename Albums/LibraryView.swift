import SwiftUI

/// The two-column album grid, modeled on Apple Music's Library › Albums.
/// Tapping an album opens it in Apple Music; there is no album page.
///
/// Measurements are from iOS 26 and 27.2 screenshots of Music's two-column
/// tiles on a 402 pt iPhone: 20 pt margins, a 12 pt gap between columns,
/// 175 pt tiles with 7 pt continuous corners and no shadow, then title and
/// artist in 13 pt on one line each.
struct LibraryView: View {
    @Environment(AlbumStore.self) private var store
    @Environment(\.openURL) private var openURL
    @AppStorage("librarySort") private var sort: LibrarySort = .recentlyAdded
    @AppStorage("libraryFilter") private var listenedFilter: LibraryFilter = .all
    @State private var searchText = ""
    @State private var isAddingAlbum = false
    @State private var albumPendingDeletion: Album?

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 12, alignment: .top),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if !AppGroup.isShared {
                    SharingUnavailableNotice()
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(visibleAlbums) { album in
                        Button {
                            openURL(album.url)
                        } label: {
                            AlbumGridCell(album: album)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens in Apple Music")
                        .contextMenu {
                            AlbumMenuItems(album: album, store: store) {
                                albumPendingDeletion = album
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .navigationTitle("Albums")
            // In the drawer under the large title, where Music keeps "Find in
            // Albums"; iOS 26's default on iPhone is a bar at the bottom.
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Find in Albums")
            .refreshable {
                store.reload()
                await store.resolvePendingAlbums()
            }
            .toolbar { toolbarContent }
            .overlay { emptyState }
            .sheet(isPresented: $isAddingAlbum) {
                AddAlbumView()
                    .environment(store)
            }
            .confirmDeletion(of: $albumPendingDeletion, in: store)
        }
    }

    /// The search text as searched: a lone space searches for nothing.
    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleAlbums: [Album] {
        var albums = store.albums.filter { listenedFilter.includes($0) }
        let query = searchQuery
        if !query.isEmpty {
            albums = albums.filter {
                $0.title.localizedStandardContains(query) || $0.artist.localizedStandardContains(query)
            }
        }
        return sort.sorted(albums)
    }

    // Filter, then "…" for sorting, as Music has them; then Add, which Music
    // doesn't need. On iOS 26 the three share one glass capsule.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Picker("Filter", selection: $listenedFilter) {
                    ForEach(LibraryFilter.allCases) { option in
                        Label(option.label, systemImage: option.systemImage).tag(option)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label(
                    "Filter",
                    systemImage: listenedFilter == .all
                        ? "line.3.horizontal.decrease"
                        : "line.3.horizontal.decrease.circle.fill"
                )
            }

            Menu {
                Picker("Sort By", selection: $sort) {
                    ForEach(LibrarySort.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("More", systemImage: "ellipsis")
            }

            Button {
                isAddingAlbum = true
            } label: {
                Label("Add Album", systemImage: "plus")
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.albums.isEmpty {
            ContentUnavailableView {
                Label("No Albums Yet", systemImage: "square.stack")
            } description: {
                Text("In Apple Music, tap Share on an album and choose Albums. Or paste a link here.")
            } actions: {
                Button("Add Album") { isAddingAlbum = true }
                    .buttonStyle(.borderedProminent)
            }
        } else if visibleAlbums.isEmpty {
            if !searchQuery.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
            } else if listenedFilter == .notListened {
                ContentUnavailableView(
                    "All Caught Up",
                    systemImage: "checkmark.circle",
                    description: Text("You've listened to everything you saved.")
                )
            } else {
                ContentUnavailableView(
                    "Nothing Listened Yet",
                    systemImage: "circle",
                    description: Text("Albums you mark as listened show up here.")
                )
            }
        }
    }
}

/// Shown when this install has no App Group, so the share extension and the app
/// each have a library of their own. Without it, albums shared from Apple Music
/// would seem to vanish.
private struct SharingUnavailableNotice: View {
    var body: some View {
        Label {
            Text("Albums shared from Apple Music can't reach this library, because this install has no App Group. Reinstall the app with SideStore to fix it. Pasted links still work.")
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12, style: .continuous))
    }
}

/// One grid item: artwork, then title and artist on a single line each.
struct AlbumGridCell: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ArtworkView(album: album, pixelSize: 600, cornerRadius: 7)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 3) {
                    Text(album.displayTitle)
                        .lineLimit(1)
                    if album.isExplicit {
                        ExplicitBadge()
                    }
                }
                .foregroundStyle(album.isPending ? .secondary : .primary)

                HStack(spacing: 3) {
                    if album.isListened {
                        Image(systemName: "checkmark.circle.fill")
                            .imageScale(.small)
                            .accessibilityLabel("Listened")
                    }
                    Text(album.displayArtist)
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
            }
            .font(.footnote)
            .padding(.top, 5)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
