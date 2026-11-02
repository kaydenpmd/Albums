import SwiftUI
import UIKit

/// One album in the grid: tap it to open the album in Apple Music, long-press
/// it for Music's menu.
///
/// The menu is UIKit's context menu rather than SwiftUI's `.contextMenu`,
/// because only UIKit can act on a tap on the card at the top of the menu
/// (`willPerformPreviewActionForMenuWith`). Music's card opens the album; so
/// does this one. SwiftUI shows the same card but gives a tap on it nothing to
/// do (Apple Developer Forums thread 766604). The cell itself is still SwiftUI,
/// hosted inside the menu's view.
struct AlbumGridItem: UIViewControllerRepresentable {
    let album: Album
    let open: () -> Void
    let toggleListened: () -> Void
    let delete: () -> Void

    func makeUIViewController(context: Context) -> AlbumGridItemController {
        AlbumGridItemController(item: self)
    }

    func updateUIViewController(_ controller: AlbumGridItemController, context: Context) {
        controller.item = self
    }

    /// The grid proposes a column width; the cell is as tall as it needs at that width.
    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController controller: AlbumGridItemController, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return controller.fittingSize(width: width)
    }
}

final class AlbumGridItemController: UIViewController, UIContextMenuInteractionDelegate {
    var item: AlbumGridItem {
        didSet { host.rootView = cell }
    }

    private lazy var host: UIHostingController<AlbumGridButton> = {
        let host = UIHostingController(rootView: self.cell)
        // The cell is laid out by the SwiftUI grid around it, so it mustn't
        // pad itself for the safe area as a screen-sized view would.
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        return host
    }()

    init(item: AlbumGridItem) {
        self.item = item
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private var cell: AlbumGridButton {
        AlbumGridButton(
            album: item.album,
            open: item.open,
            toggleListened: item.toggleListened,
            share: { [weak self] in self?.share() },
            delete: item.delete
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)

        view.addInteraction(UIContextMenuInteraction(delegate: self))
    }

    func fittingSize(width: CGFloat) -> CGSize {
        let height = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: height)
    }

    // MARK: - Long-press menu

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        let album = item.album
        return UIContextMenuConfiguration(
            identifier: album.id as NSString,
            previewProvider: { Self.makePreview(for: album) },
            actionProvider: { [weak self] _ in self?.makeMenu() }
        )
    }

    /// A tap on the card opens the album in Apple Music, as Music's own card
    /// opens the album's page. The card zooms toward the screen and Music opens
    /// with it: the open starts with the animation, not after it, the way
    /// WebKit opens a tapped link preview (WKContentViewInteraction.mm).
    /// Waiting for the card to fly back into the grid first adds a beat that
    /// Music doesn't have.
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
        animator: any UIContextMenuInteractionCommitAnimating
    ) {
        animator.preferredCommitStyle = .pop
        animator.addAnimations(item.open)
    }

    private static func makePreview(for album: Album) -> UIViewController {
        let preview = UIHostingController(rootView: AlbumMenuPreview(album: album))
        preview.safeAreaRegions = []
        preview.view.backgroundColor = .clear
        preview.preferredContentSize = preview.sizeThatFits(
            in: CGSize(width: AlbumMenuPreview.width, height: .greatestFiniteMagnitude)
        )
        return preview
    }

    /// Music's layout with Albums' own actions: a row of three with the icon
    /// over the label, then Delete from Library on its own. Only what manages
    /// the library (the owner's call, 1 Nov 2026); playing is Music's job.
    /// Music's row uses filled symbols where its list rows use outlines.
    /// Listened is the one outline in the row while the album isn't listened,
    /// so the row shows its state.
    private func makeMenu() -> UIMenu {
        let item = item
        let album = item.album

        let listened = UIAction(
            title: "Listened",
            image: UIImage(systemName: album.isListened ? "checkmark.circle.fill" : "checkmark.circle")
        ) { _ in
            item.toggleListened()
        }
        let copyLink = UIAction(title: "Copy Link", image: UIImage(systemName: "link.circle.fill")) { _ in
            UIPasteboard.general.url = album.url
        }
        let share = UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up.fill")) { [weak self] _ in
            self?.share()
        }
        let delete = UIAction(
            title: "Delete from Library",
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { _ in
            item.delete()
        }

        return UIMenu(children: [
            UIMenu(options: .displayInline, preferredElementSize: .medium, children: [listened, copyLink, share]),
            UIMenu(options: .displayInline, children: [delete]),
        ])
    }

    private func share() {
        let sheet = UIActivityViewController(activityItems: [item.album.url], applicationActivities: nil)
        // iPad shows it as a popover pointing at the album.
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = view.bounds
        present(sheet, animated: true)
    }
}

/// The cell itself: tapping it opens the album in Apple Music. Its
/// accessibility actions repeat the long-press menu for VoiceOver.
struct AlbumGridButton: View {
    let album: Album
    let open: () -> Void
    let toggleListened: () -> Void
    let share: () -> Void
    let delete: () -> Void

    var body: some View {
        Button(action: open) {
            AlbumGridCell(album: album)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens in Apple Music")
        .accessibilityAction(named: Text(album.isListened ? "Mark as Not Listened" : "Mark as Listened"), toggleListened)
        .accessibilityAction(named: Text("Copy Link")) {
            UIPasteboard.general.url = album.url
        }
        .accessibilityAction(named: Text("Share"), share)
        .accessibilityAction(named: Text("Delete from Library"), delete)
    }
}
