import Foundation

struct ClipboardEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let capturedAt: Date
    let sourceBundleIdentifier: String?
    let sourceApplicationName: String?

    init(
        id: UUID = UUID(),
        text: String,
        capturedAt: Date = Date(),
        sourceBundleIdentifier: String? = nil,
        sourceApplicationName: String? = nil
    ) {
        self.id = id
        self.text = text
        self.capturedAt = capturedAt
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.sourceApplicationName = sourceApplicationName
    }
}

struct PersistedClipboardPayload: Codable, Sendable {
    let text: String
    let capturedAt: Date
    let sourceBundleIdentifier: String?
    let sourceApplicationName: String?

    init(entry: ClipboardEntry) {
        text = entry.text
        capturedAt = entry.capturedAt
        sourceBundleIdentifier = entry.sourceBundleIdentifier
        sourceApplicationName = entry.sourceApplicationName
    }

    func entry(id: UUID) -> ClipboardEntry {
        ClipboardEntry(
            id: id,
            text: text,
            capturedAt: capturedAt,
            sourceBundleIdentifier: sourceBundleIdentifier,
            sourceApplicationName: sourceApplicationName
        )
    }
}
