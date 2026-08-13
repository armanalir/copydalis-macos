import XCTest
@testable import Copydalis

final class PopupInputInterpreterTests: XCTestCase {
    func testEscapeAlwaysMapsToCancel() {
        XCTAssertEqual(
            PopupInputInterpreter.command(forKeyCode: 53, horizontalArrowAliases: true),
            .cancel
        )
        XCTAssertEqual(
            PopupInputInterpreter.command(forKeyCode: 53, horizontalArrowAliases: false),
            .cancel
        )
    }

    func testRepeatedVIsConsumedWithoutNavigation() {
        XCTAssertEqual(
            PopupInputInterpreter.command(forKeyCode: 9, horizontalArrowAliases: true),
            .ignore
        )
    }

    func testHorizontalArrowsRespectTheSetting() {
        XCTAssertEqual(
            PopupInputInterpreter.command(forKeyCode: 124, horizontalArrowAliases: true),
            .moveOlder
        )
        XCTAssertEqual(
            PopupInputInterpreter.command(forKeyCode: 124, horizontalArrowAliases: false),
            .passThrough
        )
    }

    func testOpacityIsClampedToTheApprovedRange() {
        XCTAssertEqual(PopupAppearanceConstraints.clampOpacity(0.10), 0.40)
        XCTAssertEqual(PopupAppearanceConstraints.clampOpacity(0.75), 0.75)
        XCTAssertEqual(PopupAppearanceConstraints.clampOpacity(1.40), 1.00)
    }
}
