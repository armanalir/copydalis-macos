import Foundation
import XCTest

final class SecurityBaselineTests: XCTestCase {
    func testProductionProfileUsesHardenedRuntimeWithoutPrivilegeEntitlements() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let entitlementsURL = root.appendingPathComponent("Copydalis/Resources/Copydalis.entitlements")
        let data = try Data(contentsOf: entitlementsURL)
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        let entitlements = try XCTUnwrap(object as? [String: Any])
        let projectConfiguration = try String(
            contentsOf: root.appendingPathComponent("project.yml"),
            encoding: .utf8
        )

        XCTAssertTrue(projectConfiguration.contains("ENABLE_HARDENED_RUNTIME: YES"))
        XCTAssertTrue(projectConfiguration.contains("ENABLE_APP_SANDBOX: NO"))
        XCTAssertTrue(projectConfiguration.contains("CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO"))
        XCTAssertNil(entitlements["com.apple.security.app-sandbox"])
        XCTAssertNil(entitlements["com.apple.security.network.client"])
        XCTAssertNil(entitlements["com.apple.security.network.server"])
        XCTAssertNil(entitlements["com.apple.developer.icloud-services"])
        XCTAssertTrue(entitlements.isEmpty)
    }
}
