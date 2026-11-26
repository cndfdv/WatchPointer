import Foundation

struct WatchInputExchange {
    enum Action: Equatable { case read, write(Data) }
    private enum Phase { case idle, reading(Data, seal: ((Data, Data) -> Data?)?), writing }

    private var phase = Phase.idle
    private var checkedRead = false

    var isReading: Bool { if case .reading = phase { true } else { false } }
    var isWriting: Bool { if case .writing = phase { true } else { false } }

    mutating func begin(_ frame: Data, hasPairingRead: Bool,
                        seal: ((Data, Data) -> Data?)? = nil) -> Action? {
        guard case .idle = phase else { return nil }
        if let seal {
            guard hasPairingRead else { return nil }
            phase = .reading(frame, seal: seal)
            return .read
        }
        if hasPairingRead && !checkedRead {
            phase = .reading(frame, seal: nil)
            return .read
        }
        phase = .writing
        return .write(frame)
    }

    mutating func receivedRead(_ value: Data?) -> Data? {
        guard case let .reading(frame, seal) = phase, let value else { return nil }
        if let seal {
            guard let envelope = seal(frame, value) else { return nil }
            phase = .writing
            return envelope
        }
        guard value == Data([1]) else { return nil }
        checkedRead = true
        phase = .writing
        return frame
    }

    mutating func finish(invalidateRead: Bool = false) {
        phase = .idle
        if invalidateRead { checkedRead = false }
    }
}

enum WatchDictation {
    enum Kind: UInt8 {
        case manual = 6, begin = 10, finish = 11, cancel = 12

        var insertsText: Bool { self == .manual || self == .finish }
    }

    static func manual(_ text: String) -> Data? {
        textPayload(text).map { Data([Kind.manual.rawValue]) + $0 }
    }

    static func begin(_ id: UUID) -> Data {
        sessionHeader(.begin, id: id)
    }

    static func finish(_ id: UUID, text: String) -> Data? {
        textPayload(text).map { sessionHeader(.finish, id: id) + $0 }
    }

    static func cancel(_ id: UUID) -> Data {
        sessionHeader(.cancel, id: id)
    }

    private static func sessionHeader(_ kind: Kind, id: UUID) -> Data {
        withUnsafeBytes(of: id.uuid) { Data([kind.rawValue]) + Data($0) }
    }

    static func textPayload(_ text: String) -> Data? {
        let singleLine = text.components(separatedBy: .newlines).joined(separator: " ")
        guard !singleLine.trimmingCharacters(in: .whitespaces).isEmpty,
              !singleLine.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            return nil
        }
        return Data(singleLine.utf8)
    }
}
