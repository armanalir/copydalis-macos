import CryptoKit
import Foundation
import SQLite3

enum HistoryRepositoryError: Error, Equatable {
    case database(code: Int32)
    case invalidIdentifier
    case keyRotationFailed
}

private final class SQLiteConnection: @unchecked Sendable {
    let handle: OpaquePointer

    init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        sqlite3_close(handle)
    }
}

actor SQLiteHistoryRepository {
    private static let maximumEnvelopeByteCount = 11 * 1_024 * 1_024
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let connection: SQLiteConnection
    private var cryptor: EntryCryptor
    private let keyStore: any KeyMaterialStore
    private let logger = PrivacySafeLogger(category: "history")

    init(databaseURL: URL, keyStore: any KeyMaterialStore) throws {
        self.keyStore = keyStore
        cryptor = EntryCryptor(key: try keyStore.loadOrCreateKey())

        if databaseURL.path != ":memory:" {
            try FileManager.default.createDirectory(
                at: databaseURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(databaseURL.path, &handle, flags, nil)
        guard result == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw HistoryRepositoryError.database(code: result)
        }
        connection = SQLiteConnection(handle: handle)

        do {
            try Self.execute(handle, sql: "PRAGMA journal_mode=WAL;")
            try Self.execute(handle, sql: "PRAGMA foreign_keys=ON;")
            try Self.execute(handle, sql: "PRAGMA trusted_schema=OFF;")
            try Self.execute(handle, sql: "PRAGMA synchronous=FULL;")
            sqlite3_busy_timeout(handle, 2_000)
            try Self.execute(
                handle,
                sql: """
                CREATE TABLE IF NOT EXISTS clipboard_entries (
                    id TEXT PRIMARY KEY NOT NULL,
                    sequence INTEGER NOT NULL UNIQUE,
                    content_digest BLOB NOT NULL,
                    encrypted_payload BLOB NOT NULL
                ) STRICT;
                """
            )
            try Self.execute(
                handle,
                sql: "CREATE INDEX IF NOT EXISTS idx_clipboard_entries_sequence ON clipboard_entries(sequence DESC);"
            )
            try Self.execute(
                handle,
                sql: "CREATE INDEX IF NOT EXISTS idx_clipboard_entries_digest ON clipboard_entries(content_digest);"
            )

            if databaseURL.path != ":memory:" {
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: databaseURL.path
                )
            }
        } catch {
            throw error
        }
    }

    func insert(
        _ entry: ClipboardEntry,
        capacity: Int,
        removeExactDuplicates: Bool
    ) throws {
        let database = connection.handle
        let boundedCapacity = min(max(capacity, 10), 9_999)
        let digest = cryptor.digest(for: entry.text)
        let envelope = try cryptor.encrypt(entry)

        try transaction(database) {
            if removeExactDuplicates {
                let delete = try Self.prepare(database, sql: "DELETE FROM clipboard_entries WHERE content_digest = ?;")
                defer { sqlite3_finalize(delete) }
                try Self.bind(digest, at: 1, to: delete)
                try Self.stepDone(delete)
            }

            let nextSequence = try Self.scalarInt64(
                database,
                sql: "SELECT COALESCE(MAX(sequence), 0) + 1 FROM clipboard_entries;"
            )
            let insert = try Self.prepare(
                database,
                sql: "INSERT INTO clipboard_entries(id, sequence, content_digest, encrypted_payload) VALUES (?, ?, ?, ?);"
            )
            defer { sqlite3_finalize(insert) }
            try Self.bind(entry.id.uuidString, at: 1, to: insert)
            guard sqlite3_bind_int64(insert, 2, nextSequence) == SQLITE_OK else {
                throw HistoryRepositoryError.database(code: sqlite3_errcode(database))
            }
            try Self.bind(digest, at: 3, to: insert)
            try Self.bind(envelope, at: 4, to: insert)
            try Self.stepDone(insert)

            let trim = try Self.prepare(
                database,
                sql: """
                DELETE FROM clipboard_entries
                WHERE id NOT IN (
                    SELECT id FROM clipboard_entries ORDER BY sequence DESC LIMIT ?
                );
                """
            )
            defer { sqlite3_finalize(trim) }
            guard sqlite3_bind_int(trim, 1, Int32(boundedCapacity)) == SQLITE_OK else {
                throw HistoryRepositoryError.database(code: sqlite3_errcode(database))
            }
            try Self.stepDone(trim)
        }
    }

    func fetchNewest(limit: Int) throws -> [ClipboardEntry] {
        let database = connection.handle
        let boundedLimit = min(max(limit, 1), 9_999)
        let statement = try Self.prepare(
            database,
            sql: "SELECT id, encrypted_payload FROM clipboard_entries ORDER BY sequence DESC LIMIT ?;"
        )
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_int(statement, 1, Int32(boundedLimit)) == SQLITE_OK else {
            throw HistoryRepositoryError.database(code: sqlite3_errcode(database))
        }

        var entries: [ClipboardEntry] = []
        var rejectedCount = 0
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idText = sqlite3_column_text(statement, 0),
                let id = UUID(uuidString: String(cString: idText))
            else {
                rejectedCount += 1
                continue
            }
            let byteCount = Int(sqlite3_column_bytes(statement, 1))
            guard
                byteCount > 0,
                byteCount <= Self.maximumEnvelopeByteCount,
                let bytes = sqlite3_column_blob(statement, 1)
            else {
                rejectedCount += 1
                continue
            }
            let envelope = Data(bytes: bytes, count: byteCount)
            do {
                entries.append(try cryptor.decrypt(envelope, id: id))
            } catch {
                rejectedCount += 1
            }
        }
        if rejectedCount > 0 {
            logger.metric("history_records_rejected", count: rejectedCount)
        }
        return entries
    }

    func count() throws -> Int {
        let database = connection.handle
        return Int(try Self.scalarInt64(database, sql: "SELECT COUNT(*) FROM clipboard_entries;"))
    }

    func moveToNewest(id: UUID) throws {
        let database = connection.handle
        try transaction(database) {
            let nextSequence = try Self.scalarInt64(
                database,
                sql: "SELECT COALESCE(MAX(sequence), 0) + 1 FROM clipboard_entries;"
            )
            let statement = try Self.prepare(
                database,
                sql: "UPDATE clipboard_entries SET sequence = ? WHERE id = ?;"
            )
            defer { sqlite3_finalize(statement) }
            guard sqlite3_bind_int64(statement, 1, nextSequence) == SQLITE_OK else {
                throw HistoryRepositoryError.database(code: sqlite3_errcode(database))
            }
            try Self.bind(id.uuidString, at: 2, to: statement)
            try Self.stepDone(statement)
        }
    }

    func trim(to capacity: Int) throws {
        let database = connection.handle
        let boundedCapacity = min(max(capacity, 10), 9_999)
        let statement = try Self.prepare(
            database,
            sql: """
            DELETE FROM clipboard_entries
            WHERE id NOT IN (
                SELECT id FROM clipboard_entries ORDER BY sequence DESC LIMIT ?
            );
            """
        )
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_int(statement, 1, Int32(boundedCapacity)) == SQLITE_OK else {
            throw HistoryRepositoryError.database(code: sqlite3_errcode(database))
        }
        try Self.stepDone(statement)
    }

    func clearAndRotateKey() throws {
        let database = connection.handle
        let replacement = SymmetricKey(size: .bits256)
        do {
            try keyStore.replaceKey(with: replacement)
        } catch {
            throw HistoryRepositoryError.keyRotationFailed
        }

        cryptor = EntryCryptor(key: replacement)
        try Self.execute(database, sql: "DELETE FROM clipboard_entries;")
        try Self.execute(database, sql: "PRAGMA wal_checkpoint(TRUNCATE);")
        try Self.execute(database, sql: "VACUUM;")
        logger.info("history_cleared_and_key_rotated")
    }

    private func transaction(_ database: OpaquePointer, body: () throws -> Void) throws {
        try Self.execute(database, sql: "BEGIN IMMEDIATE;")
        do {
            try body()
            try Self.execute(database, sql: "COMMIT;")
        } catch {
            try? Self.execute(database, sql: "ROLLBACK;")
            throw error
        }
    }

    private static func execute(_ database: OpaquePointer, sql: String) throws {
        let result = sqlite3_exec(database, sql, nil, nil, nil)
        guard result == SQLITE_OK else {
            throw HistoryRepositoryError.database(code: result)
        }
    }

    private static func prepare(_ database: OpaquePointer, sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw HistoryRepositoryError.database(code: result)
        }
        return statement
    }

    private static func bind(_ string: String, at index: Int32, to statement: OpaquePointer) throws {
        let result = sqlite3_bind_text(statement, index, string, -1, transient)
        guard result == SQLITE_OK else {
            throw HistoryRepositoryError.database(code: result)
        }
    }

    private static func bind(_ data: Data, at index: Int32, to statement: OpaquePointer) throws {
        let result = data.withUnsafeBytes { buffer in
            sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(buffer.count), transient)
        }
        guard result == SQLITE_OK else {
            throw HistoryRepositoryError.database(code: result)
        }
    }

    private static func stepDone(_ statement: OpaquePointer) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw HistoryRepositoryError.database(code: result)
        }
    }

    private static func scalarInt64(_ database: OpaquePointer, sql: String) throws -> Int64 {
        let statement = try prepare(database, sql: sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw HistoryRepositoryError.database(code: sqlite3_errcode(database))
        }
        return sqlite3_column_int64(statement, 0)
    }
}
