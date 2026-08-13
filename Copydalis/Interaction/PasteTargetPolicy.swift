import Foundation

struct PasteTargetPolicy: Sendable {
    static func mayPostEvent(
        expectedProcessIdentifier: pid_t,
        frontmostProcessIdentifier: pid_t?,
        targetIsTerminated: Bool
    ) -> Bool {
        guard !targetIsTerminated, let frontmostProcessIdentifier else { return false }
        return expectedProcessIdentifier == frontmostProcessIdentifier
    }
}
