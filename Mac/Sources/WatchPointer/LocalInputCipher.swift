import CryptoKit
import Foundation
import Security

struct LocalInputCipher {
    static let challengeID = UUID(uuidString: "6B1E0006-9F4C-4C2A-9B8E-3D2A1C0F5E01")!
    static let writeID = UUID(uuidString: "6B1E0007-9F4C-4C2A-9B8E-3D2A1C0F5E01")!
    static let challengeLength = 16
    static let overhead = 28

    private static let maximumEnvelopeLength = 512
    private static let context = Data("WatchPointer local input v1".utf8)
    private let key: SymmetricKey

    init?(keyData: Data) {
        guard keyData.count == 32 else { return nil }
        key = SymmetricKey(data: keyData)
    }

    static func provisioned(in bundle: Bundle = .main) -> LocalInputCipher? {
        guard let url = bundle.url(forResource: "WatchPointerInput", withExtension: "bin"),
              let data = try? Data(contentsOf: url) else { return nil }
        return LocalInputCipher(keyData: data)
    }

    func seal(_ frame: Data, challenge: Data) -> Data? {
        guard challenge.count == Self.challengeLength,
              !frame.isEmpty,
              frame.count <= Self.maximumEnvelopeLength - Self.overhead else { return nil }
        return (try? AES.GCM.seal(frame, using: key, authenticating: Self.context + challenge))?.combined
    }

    func open(_ envelope: Data, challenge: Data) -> Data? {
        guard challenge.count == Self.challengeLength,
              envelope.count > Self.overhead,
              envelope.count <= Self.maximumEnvelopeLength,
              let box = try? AES.GCM.SealedBox(combined: envelope) else { return nil }
        return try? AES.GCM.open(box, using: key, authenticating: Self.context + challenge)
    }
}

struct LocalInputChallenges {
    private struct Entry {
        let challenge: Data
        let expiresAt: TimeInterval
    }

    private static let capacity = 8
    private static let lifetime: TimeInterval = 15
    private var entries: [UUID: Entry] = [:]

    mutating func issue(for central: UUID, now: TimeInterval) -> Data? {
        entries = entries.filter { $0.value.expiresAt > now }
        guard entries[central] != nil || entries.count < Self.capacity else { return nil }

        var bytes = [UInt8](repeating: 0, count: LocalInputCipher.challengeLength)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        let challenge = Data(bytes)
        entries[central] = Entry(challenge: challenge, expiresAt: now + Self.lifetime)
        return challenge
    }

    mutating func open(_ envelope: Data, for central: UUID, now: TimeInterval, cipher: LocalInputCipher) -> Data? {
        guard let entry = entries[central] else { return nil }
        guard now < entry.expiresAt else {
            remove(for: central)
            return nil
        }
        guard let frame = cipher.open(envelope, challenge: entry.challenge) else { return nil }
        remove(for: central)
        return frame
    }

    mutating func remove(for central: UUID) {
        entries.removeValue(forKey: central)
    }
}
