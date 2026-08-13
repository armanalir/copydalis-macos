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
}
