import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

struct RemoteInputFragment {
    let centralID: UUID
    let characteristicID: UUID
    let offset: Int
    let value: Data?

    static func assemble(_ fragments: [Self], maximumLength: Int) -> Data? {
        guard let first = fragments.first else { return nil }
        var data = Data()
        for fragment in fragments.sorted(by: { $0.offset < $1.offset }) {
            guard fragment.centralID == first.centralID,
                  fragment.characteristicID == first.characteristicID,
                  fragment.offset == data.count,
                  let value = fragment.value, !value.isEmpty,
                  value.count <= maximumLength - data.count else { return nil }
            data.append(value)
        }
        return data
    }
}

enum RemoteInputPacket: Equatable {
    case pair(String), browserBack, browserForward, spaceLeft, spaceRight, text(String)
    case browserTabPrevious, browserTabNext, missionControl

    static let maximumLength = 512

    init?(data: Data) {
        guard data.count <= Self.maximumLength, let kind = data.first else { return nil }
        let payload = data.dropFirst()
        switch kind {
        case 1 where payload.count == 6 && payload.allSatisfy({ (48...57).contains($0) }):
            self = .pair(String(decoding: payload, as: UTF8.self))
        case 2 where payload.isEmpty: self = .browserBack
        case 3 where payload.isEmpty: self = .browserForward
        case 4 where payload.isEmpty: self = .spaceLeft
        case 5 where payload.isEmpty: self = .spaceRight
        case 6:
            guard !payload.isEmpty, let text = String(data: payload, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !text.unicodeScalars.contains(where: {
                      switch $0.properties.generalCategory {
                      case .control, .lineSeparator, .paragraphSeparator: true
                      default: false
                      }
                  }) else { return nil }
            self = .text(text)
        case 7 where payload.isEmpty: self = .browserTabPrevious
        case 8 where payload.isEmpty: self = .browserTabNext
        case 9 where payload.isEmpty: self = .missionControl
        default: return nil
        }
    }

    static func assemble(_ fragments: [RemoteInputFragment]) -> RemoteInputPacket? {
        guard let data = RemoteInputFragment.assemble(fragments, maximumLength: maximumLength) else { return nil }
        return RemoteInputPacket(data: data)
    }
}

struct RemoteInputAuthorization {
    enum Decision: Equatable { case paired, allowed, invalidCode, unpaired }

    private struct Challenge {
        let code: String
        let expiresAt: TimeInterval
        var attemptsLeft = 5
    }

    private(set) var pairedCentral: UUID?
    private var challenge: Challenge?

    init(pairedCentral: UUID? = nil) {
        self.pairedCentral = pairedCentral
    }

    mutating func beginPairing(code: String, now: TimeInterval) {
        challenge = Challenge(code: code, expiresAt: now + 120)
    }

    mutating func forget() {
        pairedCentral = nil
        challenge = nil
    }

    mutating func authorize(_ packet: RemoteInputPacket, from centralID: UUID, now: TimeInterval) -> Decision {
        guard case .pair(let code) = packet else {
            return pairedCentral == centralID ? .allowed : .unpaired
        }
        guard var active = challenge, now < active.expiresAt else {
            challenge = nil
            return .invalidCode
        }
        active.attemptsLeft -= 1
        challenge = active.attemptsLeft > 0 ? active : nil
        guard code == active.code else { return .invalidCode }
        pairedCentral = centralID
        challenge = nil
        return .paired
    }
}

enum RemoteKeyboard {
    enum Result { case accepted, permissionDenied, unavailable, historyUnavailable, revoked }

    private static let missionControl = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
    private static let browsers: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome", "org.mozilla.firefox",
        "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser", "com.vivaldi.Vivaldi",
    ]

    static func perform(_ packet: RemoteInputPacket, stillAuthorized: () -> Bool) -> Result {
        guard stillAuthorized() else { return .revoked }
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { return .permissionDenied }
        switch packet {
        case .pair: return .unavailable
        case .browserBack: return navigateHistory("[", stillAuthorized: stillAuthorized)
        case .browserForward: return navigateHistory("]", stillAuthorized: stillAuthorized)
        case .spaceLeft: return shortcut(kVK_LeftArrow, .maskControl)
        case .spaceRight: return shortcut(kVK_RightArrow, .maskControl)
        case .text(let text): return typeText(text, stillAuthorized: stillAuthorized)
        case .browserTabPrevious: return switchBrowserTab([.maskControl, .maskShift], stillAuthorized: stillAuthorized)
        case .browserTabNext: return switchBrowserTab(.maskControl, stillAuthorized: stillAuthorized)
        case .missionControl: return NSWorkspace.shared.open(missionControl) ? .accepted : .unavailable
        }
    }

    private static func navigateHistory(_ symbol: String, stillAuthorized: () -> Bool) -> Result {
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier, browsers.contains(id)
        else { return .unavailable }
        let pid = app.processIdentifier
        let browser = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(browser, 0.3)
        let commandOnly: AXMenuItemModifiers = []
        guard let menuBar = elementAttribute(kAXMenuBarAttribute, of: browser),
              let item = children(of: menuBar).lazy.flatMap({ children(of: $0) })
                .lazy.flatMap({ children(of: $0) }).first(where: {
                    (attribute(kAXMenuItemCmdCharAttribute, of: $0) as? String) == symbol
                        && (attribute(kAXMenuItemCmdModifiersAttribute, of: $0) as? UInt32)
                            == commandOnly.rawValue
                }) else { return .unavailable }
        guard (attribute(kAXEnabledAttribute, of: item) as? Bool) == true else { return .historyUnavailable }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return .unavailable }
        guard stillAuthorized() else { return .revoked }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success ? .accepted : .unavailable
    }

    private static func switchBrowserTab(_ flags: CGEventFlags, stillAuthorized: () -> Bool) -> Result {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let id = app.bundleIdentifier, browsers.contains(id) else { return .unavailable }
        guard stillAuthorized() else { return .revoked }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
        else { return .unavailable }
        return shortcut(kVK_Tab, flags)
    }

    private static func shortcut(_ key: Int, _ flags: CGEventFlags) -> Result {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: false)
        else { return .unavailable }
        for event in [down, up] {
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
        return .accepted
    }

    private static func typeText(_ text: String, stillAuthorized: () -> Bool) -> Result {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.3)
        guard let field = focusedElement(in: system),
              let role = attribute(kAXRoleAttribute, of: field) as? String,
              [kAXTextFieldRole, kAXTextAreaRole].contains(role),
              (attribute(kAXSubroleAttribute, of: field) as? String) != kAXSecureTextFieldSubrole,
              (attribute(kAXEnabledAttribute, of: field) as? Bool) != false,
              isSettable(kAXValueAttribute, of: field),
              let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        else { return .unavailable }

        var pid: pid_t = 0
        guard AXUIElementGetPid(field, &pid) == .success, pid > 0,
              let current = focusedElement(in: system), CFEqual(current, field),
              !IsSecureEventInputEnabled() else { return .unavailable }
        guard stillAuthorized() else { return .revoked }

        // Quartz may truncate long keyboard payloads. Keep surrogate pairs together across events.
        let characters = Array(text.utf16)
        characters.withUnsafeBufferPointer { buffer in
            guard let start = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                var end = min(offset + 20, buffer.count)
                if end < buffer.count, (0xDC00...0xDFFF).contains(buffer[end]) {
                    end -= 1
                }
                for event in [down, up] {
                    event.flags = []
                    event.keyboardSetUnicodeString(stringLength: end - offset, unicodeString: start + offset)
                    event.postToPid(pid)
                }
                offset = end
            }
        }
        return .accepted
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func focusedElement(in system: AXUIElement) -> AXUIElement? {
        elementAttribute(kAXFocusedUIElementAttribute, of: system)
    }

    private static func elementAttribute(_ name: String, of element: AXUIElement) -> AXUIElement? {
        guard let value = attribute(name, of: element), CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        attribute(kAXChildrenAttribute, of: element) as? [AXUIElement] ?? []
    }

    private static func isSettable(_ name: String, of element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success && settable.boolValue
    }
}
