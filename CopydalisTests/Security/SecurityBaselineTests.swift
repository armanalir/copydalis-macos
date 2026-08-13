import Foundation
import XCTest

final class SecurityBaselineTests: XCTestCase {
    func testProductionEntitlementsHaveSandboxAndNoNetworkAccess() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let entitlementsURL = root.appendingPathComponent("Copydalis/Resources/Copydalis.entitlements")
        let data = try Data(contentsOf: entitlementsURL)
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        let entitlements = try XCTUnwrap(object as? [String: Any])

        XCTAssertEqual(entitlements["com.apple.security.app-sandbox"] as? Bool, true)
        XCTAssertNil(entitlements["com.apple.security.network.client"])
        XCTAssertNil(entitlements["com.apple.security.network.server"])
        XCTAssertNil(entitlements["com.apple.developer.icloud-services"])
    }
}
