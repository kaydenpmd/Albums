import Foundation
import Observation
import os
import UIKit

/// Saves whatever was shared, as quickly as it can, then gets out of the way.
@MainActor
@Observable
final class ShareModel {
    enum Phase: Equatable {
        case looking
        case saved(Album)
        case alreadySaved(Album)
        /// Apple Music couldn't be reached, so only the link was saved. The app
        /// fills in the details the next time it opens.
        case savedForLater
        case failed(String)
    }

    private(set) var phase: Phase = .looking

    @ObservationIgnored var onFinish: () -> Void = {}
    @ObservationIgnored var onCancel: () -> Void = {}
    @ObservationIgnored private var finishTask: Task<Void, Never>?
    /// Set once the extension has been told to close, by Cancel, Done or the
    /// timer. Checked after every wait, so a lookup that finishes after Cancel
    /// doesn't save anything.
    @ObservationIgnored private var isFinished = false

    private nonisolated static let log = Logger(subsystem: "com.local.albums", category: "share")

    func save(from providers: [NSItemProvider], texts: [String]) async {
        guard AppGroup.isShared else {
            Self.log.error("share extension has no app group; refusing to save into a library the app can't see")
            phase = .failed("Albums can't reach its library from the share sheet, because this install has no App Group. Reinstall it with SideStore.")
            return
        }

        // Logged because what each app hands a share extension isn't documented
        // anywhere; this line is the record of what actually arrived.
        let types = providers.flatMap(\.registeredTypeIdentifiers)
        Self.log.notice("shared \(providers.count) item(s) of type \(types.joined(separator: ", "), privacy: .public)")

        var urls = await SharedItemReader.urls(from: providers)
        urls += texts.flatMap { AppleMusicLink.urls(in: $0) }
        guard !isFinished else { return }
        guard let link = SharedItemReader.bestLink(in: urls) else {
            Self.log.error("no Apple Music link among: \(urls.map(\.absoluteString).joined(separator: " "), privacy: .public)")
            phase = .failed("There's no Apple Music link in what was shared.")
            return
        }

        let store = AlbumStore()
        // An album link names the album, so a repeat needs no lookup at all,
        // unless what's saved is still waiting for its details.
        if case .album(let id) = link.target, let existing = store.album(withID: id), !existing.isPending {
            phase = .alreadySaved(existing)
            finish(after: .seconds(1.4))
            return
        }

        do {
            let album = try await AlbumMetadataService().fetchAlbum(for: link)
            guard !isFinished else { return }
            switch store.add(album) {
            case .added(let added):
                phase = .saved(added)
                // On disk before the extension goes away, so the app shows it
                // at once. Joins the card's own load rather than fetching twice.
                _ = await ArtworkLoader.shared.image(for: added, pixelSize: ArtworkLoader.storedPixelSize)
            case .alreadySaved(let existing):
                phase = .alreadySaved(existing)
            }
            finish(after: .seconds(1.4))
        } catch let error as AlbumMetadataService.LookupError where error.isRetryable {
            guard !isFinished else { return }
            Self.log.notice("saving \(link.url.absoluteString, privacy: .public) without details: \(error.localizedDescription, privacy: .public)")
            store.add(.pending(for: link))
            phase = .savedForLater
            finish(after: .seconds(2.5))
        } catch {
            guard !isFinished else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    func done() {
        finish(after: .zero)
    }

    func cancel() {
        guard !isFinished else { return }
        isFinished = true
        finishTask?.cancel()
        onCancel()
    }

    private func finish(after delay: Duration) {
        finishTask?.cancel()
        finishTask = Task {
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled, !isFinished else { return }
            isFinished = true
            onFinish()
        }
    }
}
