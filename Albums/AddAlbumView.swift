import SwiftUI
import UniformTypeIdentifiers

/// Adding an album by pasting its link, for when the share sheet isn't handy.
struct AddAlbumView: View {
    @Environment(AlbumStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isLooking = false
    @State private var problem: String?
    /// The lookup in progress, cancelled with the sheet so a closed sheet can't still save.
    @State private var lookupTask: Task<Void, Never>?
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("music.apple.com/…", text: $text)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($isFieldFocused)
                        .onSubmit(add)
                        .disabled(isLooking)

                    // PasteButton reads the clipboard without iOS asking for permission first.
                    PasteButton(supportedContentTypes: [.url, .plainText]) { providers in
                        Task { await paste(providers) }
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonBorderShape(.capsule)
                    .disabled(isLooking)
                } footer: {
                    Text("Paste a link to an album or song. In Apple Music, tap Share, then Copy.")
                }

                if let problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Add Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        lookupTask?.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isLooking {
                        ProgressView()
                    } else {
                        Button("Add", action: add)
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .onAppear { isFieldFocused = true }
            // Swiping the sheet away doesn't go through Cancel.
            .onDisappear { lookupTask?.cancel() }
        }
        .presentationDetents([.medium, .large])
    }

    private func paste(_ providers: [NSItemProvider]) async {
        let urls = await SharedItemReader.urls(from: providers)
        guard let link = SharedItemReader.bestLink(in: urls) else {
            problem = "There's no Apple Music link on the clipboard."
            return
        }
        text = link.url.absoluteString
        add()
    }

    private func add() {
        guard !isLooking else { return }
        guard let link = SharedItemReader.bestLink(in: AppleMusicLink.urls(in: text)) else {
            problem = "That isn't an Apple Music link."
            return
        }
        problem = nil
        isLooking = true
        lookupTask = Task {
            defer { isLooking = false }
            // Cancelling makes the request fail as if offline, so every path
            // checks first: a cancelled add saves nothing, not even a pending one.
            do {
                let album = try await AlbumMetadataService().fetchAlbum(for: link)
                guard !Task.isCancelled else { return }
                switch store.add(album) {
                case .added:
                    dismiss()
                case .alreadySaved(let existing):
                    problem = "\u{201C}\(existing.displayTitle)\u{201D} is already in your library."
                }
            } catch let error as AlbumMetadataService.LookupError where error.isRetryable {
                guard !Task.isCancelled else { return }
                // The link is good; keep it and fill in the details once Apple Music answers.
                if case .alreadySaved = store.add(.pending(for: link)) {
                    problem = "That album is already in your library."
                } else {
                    dismiss()
                }
            } catch {
                guard !Task.isCancelled else { return }
                problem = error.localizedDescription
            }
        }
    }
}
