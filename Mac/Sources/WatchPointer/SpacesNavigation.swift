import Carbon.HIToolbox
import CoreGraphics

enum SpacesNavigation {
    static func events(for arrow: Int) -> [CGEvent]? {
        guard arrow == kVK_LeftArrow || arrow == kVK_RightArrow,
              let source = CGEventSource(stateID: .hidSystemState) else { return nil }

        // Mission Control needs explicit Control key events and the arrow's Fn and numeric-pad flags.
        let arrowFlags: CGEventFlags = [.maskControl, .maskSecondaryFn, .maskNumericPad]
        let keystrokes: [(key: Int, down: Bool, flags: CGEventFlags)] = [
            (kVK_Control, true, .maskControl),
            (arrow, true, arrowFlags),
            (arrow, false, arrowFlags),
            (kVK_Control, false, []),
        ]

        var events: [CGEvent] = []
        for keystroke in keystrokes {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keystroke.key),
                                      keyDown: keystroke.down) else { return nil }
            event.flags = keystroke.flags
            events.append(event)
        }
        return events
    }

    static func post(arrow: Int, stillAuthorized: () -> Bool) -> RemoteKeyboard.Result {
        guard let events = events(for: arrow) else { return .unavailable }
        guard stillAuthorized() else { return .revoked }
        for event in events {
            event.post(tap: .cghidEventTap)
        }
        return .accepted
    }
}
