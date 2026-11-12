import AppKit
import ClipboardCore
import Observation
import Vision

/// Reads the text in image items on this Mac, so it can be searched and copied.
@MainActor
final class TextRecognizer {
    private let store: HistoryStore
    private var isRunning = false

    init(store: HistoryStore) {
        self.store = store
    }

    func start() {
        observe()
        scan()
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

    private func scan() {
        guard !isRunning, let persistence = store.persistence else { return }
        let pending = store.items
            .filter { $0.kind == .image && $0.recognizedText == nil }
            .compactMap { item in item.imageFile.map { (item.id, persistence.imageURL(for: $0)) } }
        guard !pending.isEmpty else { return }
        isRunning = true
        Task.detached(priority: .utility) { [weak self] in
            // Saved in small batches, so a long first pass over existing history doesn't rewrite
            // the history file for every image.
            for batch in stride(from: 0, to: pending.count, by: 10).map({ Array(pending[$0..<min($0 + 10, pending.count)]) }) {
                var texts: [ClipItem.ID: String] = [:]
                for (id, url) in batch {
                    texts[id] = Self.recognizeText(at: url)
                }
                await self?.apply(texts)
            }
            await self?.finish()
        }
    }

    private func apply(_ texts: [ClipItem.ID: String]) {
        store.setRecognizedText(texts)
    }

    private func finish() {
        isRunning = false
        // Picks up images copied while this pass was running.
        scan()
    }

    nonisolated static func recognizeText(at url: URL) -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        do {
            try VNImageRequestHandler(cgImage: image).perform([request])
        } catch {
            return ""
        }
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
