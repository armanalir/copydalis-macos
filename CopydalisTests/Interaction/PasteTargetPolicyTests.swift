import XCTest
@testable import Copydalis

final class PasteTargetPolicyTests: XCTestCase {
    func testAllowsOnlyTheExpectedLiveFrontmostProcess() {
        XCTAssertTrue(
            PasteTargetPolicy.mayPostEvent(
                expectedProcessIdentifier: 100,
                frontmostProcessIdentifier: 100,
                targetIsTerminated: false
            )
        )
    }

    func testFailsClosedForFocusChangeMissingTargetOrTermination() {
        XCTAssertFalse(
            PasteTargetPolicy.mayPostEvent(
                expectedProcessIdentifier: 100,
                frontmostProcessIdentifier: 101,
                targetIsTerminated: false
            )
        )
        XCTAssertFalse(
            PasteTargetPolicy.mayPostEvent(
                expectedProcessIdentifier: 100,
                frontmostProcessIdentifier: nil,
                targetIsTerminated: false
            )
        )
        XCTAssertFalse(
            PasteTargetPolicy.mayPostEvent(
                expectedProcessIdentifier: 100,
                frontmostProcessIdentifier: 100,
                targetIsTerminated: true
            )
        )
    }

    func testActivationRetryIsStrictlyBounded() {
        XCTAssertFalse(PasteTargetPolicy.shouldRetryActivation(attempt: -1, maximumAttempts: 10))
        XCTAssertFalse(PasteTargetPolicy.shouldRetryActivation(attempt: 0, maximumAttempts: 10))
        XCTAssertTrue(PasteTargetPolicy.shouldRetryActivation(attempt: 1, maximumAttempts: 10))
        XCTAssertTrue(PasteTargetPolicy.shouldRetryActivation(attempt: 9, maximumAttempts: 10))
        XCTAssertFalse(PasteTargetPolicy.shouldRetryActivation(attempt: 10, maximumAttempts: 10))
    }

    func testPasteMenuPolicyMatchesOnlyEnabledCommandV() {
        XCTAssertTrue(
            PasteMenuItemPolicy.matchesCommandV(
                commandCharacter: "V",
                modifiers: 0,
                isEnabled: true
            )
        )
        XCTAssertTrue(
            PasteMenuItemPolicy.matchesCommandV(
                commandCharacter: "v",
                modifiers: 0,
                isEnabled: true
            )
        )
        XCTAssertFalse(
            PasteMenuItemPolicy.matchesCommandV(
                commandCharacter: "V",
                modifiers: 1,
                isEnabled: true
            )
        )
        XCTAssertFalse(
            PasteMenuItemPolicy.matchesCommandV(
                commandCharacter: "C",
                modifiers: 0,
                isEnabled: true
            )
        )
        XCTAssertFalse(
            PasteMenuItemPolicy.matchesCommandV(
                commandCharacter: "V",
                modifiers: 0,
                isEnabled: false
            )
        )
    }
}
