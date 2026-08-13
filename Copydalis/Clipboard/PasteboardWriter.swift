import AppKit

@MainActor
final class PasteboardWriter {
    private(set) var internallyWrittenChangeCount: Int?

    @discardableResult
    func write(_ text: String) -> Int {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        internallyWrittenChangeCount = pasteboard.changeCount
        return pasteboard.changeCount
    }

    func consumeInternalMutation(changeCount: Int) -> Bool {
        guard internallyWrittenChangeCount == changeCount else { return false }
        internallyWrittenChangeCount = nil
        return true
    }
}
