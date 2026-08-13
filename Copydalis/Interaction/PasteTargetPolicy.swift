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

    static func shouldRetryActivation(attempt: Int, maximumAttempts: Int) -> Bool {
        attempt >= 1 && attempt < maximumAttempts
    }
}
