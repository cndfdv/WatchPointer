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
