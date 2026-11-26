import CoreGraphics

// The raw values match RemoteInputPacket on the Mac.
enum WatchInputCommand: UInt8 {
    case spaceLeft = 4, spaceRight = 5
    case browserTabPrevious = 7, browserTabNext = 8, missionControl = 9

    var isBrowserTab: Bool { self == .browserTabPrevious || self == .browserTabNext }
    var requiresUpdatedMac: Bool { isBrowserTab || self == .missionControl }
}

struct PadGesture<ContactID: Hashable> {
    enum Outcome: Equatable {
        case click
        case drop
        case swipe(WatchInputCommand)
    }

    private enum Direction { case left, right, up }

    private struct Contact {
        let start: CGPoint
        var end: CGPoint

        var direction: Direction? {
            let dx = end.x - start.x
            let dy = end.y - start.y
            if abs(dx) >= 24, abs(dx) >= 1.5 * abs(dy) { return dx > 0 ? .right : .left }
            if dy <= -24, -dy >= 1.5 * abs(dx) { return .up }
            return nil
        }
    }

    private var contacts: [ContactID: Contact] = [:]
    private var moved = false
    private var cancelled = false
    private var overlapped = false
    private var finished = false
    private(set) var dragging = false

    var canHold: Bool { contacts.count == 1 && !moved && !cancelled && !dragging && !finished }

    mutating func record(_ id: ContactID, at location: CGPoint, active: Bool) {
        guard active || contacts[id] != nil else { return }
        var contact = contacts[id] ?? Contact(start: location, end: location)
        contact.end = location
        contacts[id] = contact
        moved = moved || hypot(location.x - contact.start.x, location.y - contact.start.y) >= 8
    }

    mutating func recordOverlap() { overlapped = true }

    mutating func beginHold() -> Bool {
        guard canHold else { return false }
        dragging = true
        return true
    }

    mutating func cancel() -> Outcome? {
        cancelled = true
        guard dragging else { return nil }
        dragging = false
        return .drop
    }

    mutating func finish() -> Outcome? {
        guard !finished else { return nil }
        finished = true
        if dragging {
            dragging = false
            return .drop
        }
        guard !cancelled else { return nil }
        if contacts.count == 1, !moved { return .click }
        guard let direction = contacts.values.first?.direction else { return nil }
        if contacts.count == 2 {
            guard overlapped, contacts.values.allSatisfy({ $0.direction == direction }) else { return nil }
        }
        switch (contacts.count, direction) {
        case (1, .left): return .swipe(.browserTabNext)
        case (1, .right): return .swipe(.browserTabPrevious)
        case (2, .left): return .swipe(.spaceRight)
        case (2, .right): return .swipe(.spaceLeft)
        case (2, .up): return .swipe(.missionControl)
        default: return nil
        }
    }
}
