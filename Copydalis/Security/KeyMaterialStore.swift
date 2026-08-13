import CryptoKit
import Foundation
import Security

enum KeyMaterialStoreError: Error, Equatable {
    case keychain(OSStatus)
    case invalidKeyMaterial
}

protocol KeyMaterialStore: Sendable {
    func loadOrCreateKey() throws -> SymmetricKey
    func replaceKey(with key: SymmetricKey) throws
}

final class KeychainKeyMaterialStore: KeyMaterialStore, @unchecked Sendable {
    private let service: String
    private let account: String
    private let lock = NSLock()

    init(
        service: String = "com.copydalis.app.history-encryption",
        account: String = "local-device-key-v1"
    ) {
        self.service = service
        self.account = account
    }

    func loadOrCreateKey() throws -> SymmetricKey {
        lock.lock()
        defer { lock.unlock() }

        if let existing = try loadData() {
            guard existing.count == 32 else {
                throw KeyMaterialStoreError.invalidKeyMaterial
            }
            return SymmetricKey(data: existing)
        }

        let key = SymmetricKey(size: .bits256)
        try add(data: key.dataRepresentation)
        return key
    }

    func replaceKey(with key: SymmetricKey) throws {
        lock.lock()
        defer { lock.unlock() }

        let query = baseQuery
        let attributes: [CFString: Any] = [
            kSecValueData: key.dataRepresentation,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable: kCFBooleanFalse as Any
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            try add(data: key.dataRepresentation)
        } else if status != errSecSuccess {
            throw KeyMaterialStoreError.keychain(status)
        }
    }

    private var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: kCFBooleanFalse as Any
        ]
    }

    private func loadData() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData] = kCFBooleanTrue
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeyMaterialStoreError.keychain(status)
        }
        guard let data = result as? Data else {
            throw KeyMaterialStoreError.invalidKeyMaterial
        }
        return data
    }

    private func add(data: Data) throws {
        var attributes = baseQuery
        attributes[kSecValueData] = data
        attributes[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeyMaterialStoreError.keychain(status)
        }
    }
}

private extension SymmetricKey {
    var dataRepresentation: Data {
        withUnsafeBytes { Data($0) }
    }
}
