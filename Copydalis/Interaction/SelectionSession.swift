import Foundation

enum SelectionDirection: Sendable {
    case newer
    case older
}

enum SelectionSessionOutcome: Equatable, Sendable {
    case commit(ClipboardEntry)
    case cancel
    case none
}

struct SelectionSession: Sendable {
    enum State: Equatable, Sendable {
        case idle
        case active
        case committed
        case cancelled
    }

    private(set) var entries: [ClipboardEntry] = []
    private(set) var selectedIndex = 0
    private(set) var state: State = .idle
    let wraparound: Bool

    init(entries: [ClipboardEntry], wraparound: Bool) {
        self.entries = entries
        self.wraparound = wraparound
        state = .active
    }

    var selectedEntry: ClipboardEntry? {
        guard state == .active, entries.indices.contains(selectedIndex) else { return nil }
        return entries[selectedIndex]
    }

    mutating func move(_ direction: SelectionDirection) {
        guard state == .active, !entries.isEmpty else { return }
        switch direction {
        case .older:
            if selectedIndex < entries.count - 1 {
                selectedIndex += 1
            } else if wraparound {
                selectedIndex = 0
            }
        case .newer:
            if selectedIndex > 0 {
                selectedIndex -= 1
            } else if wraparound {
                selectedIndex = entries.count - 1
            }
        }
    }

    mutating func selectNewest() {
        guard state == .active else { return }
        selectedIndex = 0
    }

    mutating func selectOldest() {
        guard state == .active, !entries.isEmpty else { return }
        selectedIndex = entries.count - 1
    }

    mutating func movePage(_ offset: Int) {
        guard state == .active, !entries.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + offset, 0), entries.count - 1)
    }

    mutating func commit() -> SelectionSessionOutcome {
        guard state == .active else { return .none }
        state = .committed
        guard entries.indices.contains(selectedIndex) else { return .cancel }
        return .commit(entries[selectedIndex])
    }

    mutating func cancel() -> SelectionSessionOutcome {
        guard state == .active else { return .none }
        state = .cancelled
        return .cancel
    }
}
