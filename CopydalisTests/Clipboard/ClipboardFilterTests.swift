import XCTest
@testable import Copydalis

final class ClipboardFilterTests: XCTestCase {
    func testAcceptsPlainUnicodeText() {
        let filter = ClipboardFilter()

        XCTAssertEqual(
            filter.evaluate(typeNames: ["public.utf8-plain-text"], plainText: "Türkçe 🔐"),
            .accept("Türkçe 🔐")
        )
    }

    func testRejectsProtectedTypeBeforeContent() {
        let filter = ClipboardFilter()

        XCTAssertEqual(
            filter.evaluate(
                typeNames: ["org.nspasteboard.ConcealedType", "public.utf8-plain-text"],
                plainText: "password"
            ),
            .rejectProtectedType
        )
    }

    func testRejectsPasswordManagerTypeCaseInsensitively() {
        let filter = ClipboardFilter()

        XCTAssertEqual(
            filter.evaluate(typeNames: ["COM.AGILEBITS.ONEPASSWORD"], plainText: "secret"),
            .rejectProtectedType
        )
    }

    func testRejectsOrganizationConfiguredType() {
        let filter = ClipboardFilter(additionalProtectedTypes: ["com.organization.classified"])

        XCTAssertEqual(
            filter.evaluate(typeNames: ["com.organization.classified"], plainText: "value"),
            .rejectProtectedType
        )
    }

    func testRejectsEmptyUnsupportedAndOversizedValues() {
        let filter = ClipboardFilter(maximumByteCount: 4)

        XCTAssertEqual(filter.evaluate(typeNames: [], plainText: nil), .rejectUnsupported)
        XCTAssertEqual(filter.evaluate(typeNames: [], plainText: ""), .rejectEmpty)
        XCTAssertEqual(filter.evaluate(typeNames: [], plainText: "12345"), .rejectOversized)
    }
}
