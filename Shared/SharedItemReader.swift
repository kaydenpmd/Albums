import Foundation
import UniformTypeIdentifiers

/// Pulls links out of shared or pasted items. The Music app shares a URL, but other apps hand
/// over text like "Listen on Apple Music: https://…", so text is searched for links too.
enum SharedItemReader {
    static func urls(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = await loadURL(from: provider) {
                urls.append(url)
            }
        }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = await loadText(from: provider) {
                urls += AppleMusicLink.urls(in: text)
            }
        }
        return urls
    }

    /// The first Apple Music link among `urls`, preferring albums and songs over other kinds of link.
    static func bestLink(in urls: [URL]) -> AppleMusicLink? {
        let links = urls.compactMap(AppleMusicLink.init(url:))
        return links.first { link in
            if case .unsupported = link.target { return false }
            return true
        } ?? links.first
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                let url: URL?
                switch item {
                case let value as URL: url = value
                case let value as Data: url = URL(dataRepresentation: value, relativeTo: nil)
                case let value as String: url = URL(string: value)
                default: url = nil
                }
                continuation.resume(returning: url)
            }
        }
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                let text: String?
                switch item {
                case let value as String: text = value
                case let value as NSAttributedString: text = value.string
                case let value as Data: text = String(data: value, encoding: .utf8)
                case let value as URL: text = value.absoluteString
                default: text = nil
                }
                continuation.resume(returning: text)
            }
        }
    }
}

extension Error {
    /// True for errors that mean "no usable connection right now" rather than a bad link.
    var isConnectivityProblem: Bool {
        guard let error = self as? URLError else { return false }
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
             .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff,
             .callIsActive, .secureConnectionFailed:
            return true
        default:
            return false
        }
    }
}
