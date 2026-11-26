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

        var travel: CGVector { CGVector(dx: end.x - start.x, dy: end.y - start.y) }
    }

    private static var movementThreshold: CGFloat { 8 }

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
        moved = moved || hypot(contact.travel.dx, contact.travel.dy) >= Self.movementThreshold
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
        guard let direction = swipeDirection() else { return nil }
        switch (contacts.count, direction) {
        case (1, .left): return .swipe(.browserTabNext)
        case (1, .right): return .swipe(.browserTabPrevious)
        case (2, .left): return .swipe(.spaceRight)
        case (2, .right): return .swipe(.spaceLeft)
        case (2, .up): return .swipe(.missionControl)
        default: return nil
        }
    }

    private func swipeDirection() -> Direction? {
        let strokes = contacts.values.map(\.travel)
        switch strokes.count {
        case 1:
            return Self.direction(of: strokes[0], minimumDistance: 24)
        case 2 where overlapped:
            // The second finger can touch down later and cover less distance.
            let center = CGVector(dx: (strokes[0].dx + strokes[1].dx) / 2,
                                  dy: (strokes[0].dy + strokes[1].dy) / 2)
            guard let direction = Self.direction(of: center, minimumDistance: 24),
                  strokes.allSatisfy({
                      Self.direction(of: $0, minimumDistance: Self.movementThreshold) == direction
                  }) else { return nil }
            return direction
        default:
            return nil
        }
    }

    private static func direction(of travel: CGVector, minimumDistance: CGFloat) -> Direction? {
        let (dx, dy) = (travel.dx, travel.dy)
        if abs(dx) >= minimumDistance, abs(dx) >= 1.5 * abs(dy) { return dx > 0 ? .right : .left }
        if dy <= -minimumDistance, -dy >= 1.5 * abs(dx) { return .up }
        return nil
    }
}
