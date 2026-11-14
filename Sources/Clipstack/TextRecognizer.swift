import AppKit
import ClipboardCore
import Observation
import Vision

/// Reads the text in image items on this Mac, so it can be searched and copied.
@MainActor
final class TextRecognizer {
    private let store: HistoryStore
    private var isRunning = false
    /// Images that couldn't be read this launch (file missing or Vision failed). They're tried
    /// again on the next launch rather than being marked as having no text.
    private var failed: Set<ClipItem.ID> = []

    init(store: HistoryStore) {
        self.store = store
    }

    func start() {
        observe()
        scan()
    }

    /// Returns the text in an image item, reading it right away if the background pass hasn't
    /// got to it yet. Empty when the image has no text.
    func text(for item: ClipItem) async -> String {
        if let text = store.item(id: item.id)?.recognizedText { return text }
        guard let name = item.imageFile, let url = store.persistence?.imageURL(for: name) else { return "" }
        let result = await Task.detached(priority: .userInitiated) { Self.recognizeText(at: url) }.value
        guard let text = result else { return "" }
        store.setRecognizedText([item.id: text])
        return text
    }

    /// Rescans whenever the history changes, which is how new images arrive.
    private func observe() {
        withObservationTracking {
            _ = store.items
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.scan()
                self?.observe()
            }
        }
    }

    /// Images still to read, newest first, so something just copied doesn't wait behind a long
    /// first pass over older history.
    private func nextBatch() -> [(ClipItem.ID, URL)] {
        guard let persistence = store.persistence else { return [] }
        return store.items
            .lazy
            .filter { $0.kind == .image && $0.recognizedText == nil && !self.failed.contains($0.id) }
            .compactMap { item in item.imageFile.map { (item.id, persistence.imageURL(for: $0)) } }
            .prefix(5)
            .map { $0 }
    }

    private func scan() {
        guard !isRunning else { return }
        let batch = nextBatch()
        guard !batch.isEmpty else { return }
        isRunning = true
        Task.detached(priority: .utility) { [weak self] in
            var texts: [ClipItem.ID: String] = [:]
            var failed: [ClipItem.ID] = []
            for (id, url) in batch {
                if let text = Self.recognizeText(at: url) { texts[id] = text } else { failed.append(id) }
            }
            await self?.finish(texts: texts, failed: failed)
        }
    }

    private func finish(texts: [ClipItem.ID: String], failed: [ClipItem.ID]) {
        self.failed.formUnion(failed)
        // Saved a few at a time, so a long first pass over existing history doesn't rewrite the
        // history file for every image.
        store.setRecognizedText(texts)
        isRunning = false
        scan()
    }

    /// The text in the image, empty when it has none, or nil when the image couldn't be read.
    nonisolated static func recognizeText(at url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        do {
            try VNImageRequestHandler(cgImage: image).perform([request])
        } catch {
            return nil
        }
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
