import AppKit
import XCTest
@testable import Copydalis

final class HotKeyConfigurationTests: XCTestCase {
    func testBuildsDisplayNameAndCarbonFlagsFromKeyEvent() throws {
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.shift, .command],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "V",
                charactersIgnoringModifiers: "v",
                isARepeat: false,
                keyCode: 9
            )
        )

        let configuration = try XCTUnwrap(HotKeyConfiguration.from(event: event))

        XCTAssertEqual(configuration, .defaultShortcut)
        XCTAssertEqual(configuration.displayName, "⇧⌘V")
    }

    func testRejectsKeyWithoutARequiredModifier() throws {
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "V",
                charactersIgnoringModifiers: "v",
                isARepeat: false,
                keyCode: 9
            )
        )

        XCTAssertNil(HotKeyConfiguration.from(event: event))
    }
}
