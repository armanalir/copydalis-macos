import CryptoKit
import Foundation

enum EntryCryptorError: Error, Equatable {
    case malformedEnvelope
    case invalidPayload
}

struct EntryCryptor: Sendable {
    private static let digestContext = Data("Copydalis.content-digest.v1".utf8)

    private let encryptionKey: SymmetricKey
    private let digestKey: SymmetricKey

    init(key: SymmetricKey) {
        encryptionKey = key
        digestKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: key,
            salt: Data(),
            info: Self.digestContext,
            outputByteCount: 32
        )
    }

    func encrypt(_ entry: ClipboardEntry) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let plaintext = try encoder.encode(PersistedClipboardPayload(entry: entry))
        let sealedBox = try AES.GCM.seal(plaintext, using: encryptionKey)
        guard let combined = sealedBox.combined else {
            throw EntryCryptorError.malformedEnvelope
        }
        return combined
    }

    func decrypt(_ envelope: Data, id: UUID) throws -> ClipboardEntry {
        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.SealedBox(combined: envelope)
        } catch {
            throw EntryCryptorError.malformedEnvelope
        }

        let plaintext = try AES.GCM.open(sealedBox, using: encryptionKey)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let payload = try? decoder.decode(PersistedClipboardPayload.self, from: plaintext) else {
            throw EntryCryptorError.invalidPayload
        }
        return payload.entry(id: id)
    }

    func digest(for text: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(text.utf8), using: digestKey))
    }
}
