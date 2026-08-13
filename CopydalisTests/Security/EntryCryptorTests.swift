import CryptoKit
import Foundation
import XCTest
@testable import Copydalis

final class EntryCryptorTests: XCTestCase {
    private let entry = ClipboardEntry(
        id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
        text: "Savunma – confidential 🔐\nSecond line",
        capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
        sourceBundleIdentifier: "com.example.editor",
        sourceApplicationName: "Editor"
    )

    func testEncryptDecryptRoundTripPreservesPayload() throws {
        let cryptor = EntryCryptor(key: SymmetricKey(size: .bits256))
        let envelope = try cryptor.encrypt(entry)

        XCTAssertFalse(envelope.contains(Data(entry.text.utf8)))
        XCTAssertEqual(try cryptor.decrypt(envelope, id: entry.id), entry)
    }

    func testEncryptionUsesRandomNonce() throws {
        let cryptor = EntryCryptor(key: SymmetricKey(size: .bits256))

        XCTAssertNotEqual(try cryptor.encrypt(entry), try cryptor.encrypt(entry))
    }

    func testTamperingIsRejected() throws {
        let cryptor = EntryCryptor(key: SymmetricKey(size: .bits256))
        var envelope = try cryptor.encrypt(entry)
        envelope[envelope.index(before: envelope.endIndex)] ^= 0x01

        XCTAssertThrowsError(try cryptor.decrypt(envelope, id: entry.id))
    }

    func testWrongKeyIsRejected() throws {
        let writer = EntryCryptor(key: SymmetricKey(size: .bits256))
        let reader = EntryCryptor(key: SymmetricKey(size: .bits256))

        XCTAssertThrowsError(try reader.decrypt(try writer.encrypt(entry), id: entry.id))
    }

    func testDigestIsKeyedAndDeterministic() {
        let first = EntryCryptor(key: SymmetricKey(size: .bits256))
        let second = EntryCryptor(key: SymmetricKey(size: .bits256))

        XCTAssertEqual(first.digest(for: entry.text), first.digest(for: entry.text))
        XCTAssertNotEqual(first.digest(for: entry.text), second.digest(for: entry.text))
        XCTAssertNotEqual(first.digest(for: entry.text), Data(SHA256.hash(data: Data(entry.text.utf8))))
    }
}

private extension Data {
    func contains(_ other: Data) -> Bool {
        range(of: other) != nil
    }
}
