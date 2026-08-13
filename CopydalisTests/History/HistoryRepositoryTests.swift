import CryptoKit
import Foundation
import SQLite3
import XCTest
@testable import Copydalis

final class HistoryRepositoryTests: XCTestCase {
    func testInsertFetchOrderingAndCapacity() async throws {
        let fixture = try RepositoryFixture()
        for index in 0..<12 {
            try await fixture.repository.insert(
                ClipboardEntry(text: "entry-\(index)"),
                capacity: 10,
                removeExactDuplicates: false
            )
        }

        let entries = try await fixture.repository.fetchNewest(limit: 100)
        XCTAssertEqual(entries.count, 10)
        XCTAssertEqual(entries.first?.text, "entry-11")
        XCTAssertEqual(entries.last?.text, "entry-2")
    }

    func testDuplicateRemovalMovesLatestValueToNewest() async throws {
        let fixture = try RepositoryFixture()
        try await fixture.repository.insert(ClipboardEntry(text: "same"), capacity: 100, removeExactDuplicates: true)
        try await fixture.repository.insert(ClipboardEntry(text: "different"), capacity: 100, removeExactDuplicates: true)
        try await fixture.repository.insert(ClipboardEntry(text: "same"), capacity: 100, removeExactDuplicates: true)

        let entries = try await fixture.repository.fetchNewest(limit: 100)
        XCTAssertEqual(entries.map(\.text), ["same", "different"])
    }

    func testDatabaseAndWALDoNotContainPlaintext() async throws {
        let fixture = try RepositoryFixture()
        let secret = "COPYDALIS_UNIQUE_CLASSIFIED_MARKER_8A45E"
        try await fixture.repository.insert(
            ClipboardEntry(
                text: secret,
                sourceBundleIdentifier: "com.secret.application",
                sourceApplicationName: "Secret Application"
            ),
            capacity: 100,
            removeExactDuplicates: false
        )

        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: fixture.databaseURL.path + suffix)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let bytes = try Data(contentsOf: url)
            XCTAssertNil(bytes.range(of: Data(secret.utf8)))
            XCTAssertNil(bytes.range(of: Data("Secret Application".utf8)))
        }
    }

    func testTamperedCiphertextIsRejectedWithoutCrash() async throws {
        let fixture = try RepositoryFixture()
        try await fixture.repository.insert(ClipboardEntry(text: "value"), capacity: 100, removeExactDuplicates: false)

        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(fixture.databaseURL.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(
            sqlite3_exec(database, "UPDATE clipboard_entries SET encrypted_payload = x'00';", nil, nil, nil),
            SQLITE_OK
        )

        let entries = try await fixture.repository.fetchNewest(limit: 100)
        XCTAssertEqual(entries, [])
    }

    func testClearRotatesKeyAndRemovesAllEntries() async throws {
        let fixture = try RepositoryFixture()
        try await fixture.repository.insert(ClipboardEntry(text: "value"), capacity: 100, removeExactDuplicates: false)
        let oldKey = fixture.keyStore.currentKeyData

        try await fixture.repository.clearAndRotateKey()

        let count = try await fixture.repository.count()
        XCTAssertEqual(count, 0)
        XCTAssertNotEqual(fixture.keyStore.currentKeyData, oldKey)
    }

    func testMoveToNewestAndExplicitTrim() async throws {
        let fixture = try RepositoryFixture()
        var firstID: UUID?
        for index in 0..<12 {
            let entry = ClipboardEntry(text: "entry-\(index)")
            if index == 0 { firstID = entry.id }
            try await fixture.repository.insert(entry, capacity: 100, removeExactDuplicates: false)
        }
        try await fixture.repository.moveToNewest(id: try XCTUnwrap(firstID))
        try await fixture.repository.trim(to: 10)

        let entries = try await fixture.repository.fetchNewest(limit: 100)
        XCTAssertEqual(entries.count, 10)
        XCTAssertEqual(entries.first?.text, "entry-0")
        XCTAssertFalse(entries.contains { $0.text == "entry-1" })
        XCTAssertFalse(entries.contains { $0.text == "entry-2" })
    }
}

private struct RepositoryFixture {
    let directoryURL: URL
    let databaseURL: URL
    let keyStore: InMemoryKeyMaterialStore
    let repository: SQLiteHistoryRepository

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CopydalisTests-\(UUID().uuidString)", isDirectory: true)
        databaseURL = directoryURL.appendingPathComponent("History.sqlite3")
        keyStore = InMemoryKeyMaterialStore()
        repository = try SQLiteHistoryRepository(databaseURL: databaseURL, keyStore: keyStore)
    }
}

private final class InMemoryKeyMaterialStore: KeyMaterialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var key = SymmetricKey(size: .bits256)

    var currentKeyData: Data {
        lock.withLock { key.withUnsafeBytes { Data($0) } }
    }

    func loadOrCreateKey() throws -> SymmetricKey {
        lock.withLock { key }
    }

    func replaceKey(with key: SymmetricKey) throws {
        lock.withLock { self.key = key }
    }
}
