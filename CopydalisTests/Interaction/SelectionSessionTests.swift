import XCTest
@testable import Copydalis

final class SelectionSessionTests: XCTestCase {
    private let entries = [
        ClipboardEntry(text: "newest"),
        ClipboardEntry(text: "middle"),
        ClipboardEntry(text: "oldest")
    ]

    func testNewestIsSelectedImmediately() {
        let session = SelectionSession(entries: entries, wraparound: false)

        XCTAssertEqual(session.selectedEntry?.text, "newest")
    }

    func testArrowNavigationAndBoundaries() {
        var session = SelectionSession(entries: entries, wraparound: false)

        session.move(.older)
        session.move(.older)
        session.move(.older)
        XCTAssertEqual(session.selectedEntry?.text, "oldest")
        session.move(.newer)
        XCTAssertEqual(session.selectedEntry?.text, "middle")
    }

    func testWraparoundIsExplicit() {
        var session = SelectionSession(entries: entries, wraparound: true)

        session.move(.newer)
        XCTAssertEqual(session.selectedEntry?.text, "oldest")
        session.move(.older)
        XCTAssertEqual(session.selectedEntry?.text, "newest")
    }

    func testCommitCanOnlyOccurOnce() {
        var session = SelectionSession(entries: entries, wraparound: false)
        session.move(.older)

        XCTAssertEqual(session.commit(), .commit(entries[1]))
        XCTAssertEqual(session.commit(), .none)
        XCTAssertEqual(session.cancel(), .none)
    }

    func testCancelPreventsLaterModifierReleaseCommit() {
        var session = SelectionSession(entries: entries, wraparound: false)

        XCTAssertEqual(session.cancel(), .cancel)
        XCTAssertEqual(session.commit(), .none)
    }

    func testEmptySessionFailsClosed() {
        var session = SelectionSession(entries: [], wraparound: false)

        XCTAssertEqual(session.commit(), .cancel)
        XCTAssertEqual(session.state, .committed)
    }

    func testPageAndHomeEndNavigationAreBounded() {
        var session = SelectionSession(entries: entries, wraparound: false)

        session.movePage(10)
        XCTAssertEqual(session.selectedEntry?.text, "oldest")
        session.selectNewest()
        XCTAssertEqual(session.selectedEntry?.text, "newest")
        session.selectOldest()
        XCTAssertEqual(session.selectedEntry?.text, "oldest")
        session.movePage(-10)
        XCTAssertEqual(session.selectedEntry?.text, "newest")
    }
}
