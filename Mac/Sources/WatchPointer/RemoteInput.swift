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
    case dictationBegin(UUID), dictationFinish(UUID, String), dictationCancel(UUID)

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
            guard let text = Self.validText(payload) else { return nil }
            self = .text(text)
        case 7 where payload.isEmpty: self = .browserTabPrevious
        case 8 where payload.isEmpty: self = .browserTabNext
        case 9 where payload.isEmpty: self = .missionControl
        case 10 where payload.count == 16:
            self = .dictationBegin(Self.dictationID(payload))
        case 11 where payload.count > 16:
            guard let text = Self.validText(payload.dropFirst(16)) else { return nil }
            self = .dictationFinish(Self.dictationID(payload), text)
        case 12 where payload.count == 16:
            self = .dictationCancel(Self.dictationID(payload))
        default: return nil
        }
    }

    private static func dictationID(_ payload: Data) -> UUID {
        let bytes = Array(payload.prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private static func validText(_ payload: Data) -> String? {
        guard !payload.isEmpty, let text = String(data: payload, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !text.unicodeScalars.contains(where: {
                  switch $0.properties.generalCategory {
                  case .control, .lineSeparator, .paragraphSeparator: true
                  default: false
                  }
              }) else { return nil }
        return text
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

struct FocusedDictationSession<Target> {
    private struct Capture {
        let id: UUID
        let target: Target
        let expiresAt: TimeInterval
    }

    private var capture: Capture?

    mutating func begin(_ id: UUID, target: Target, now: TimeInterval) {
        capture = Capture(id: id, target: target, expiresAt: now + 120)
    }

    mutating func take(_ id: UUID, now: TimeInterval) -> Target? {
        guard let active = capture else { return nil }
        if now >= active.expiresAt {
            capture = nil
            return nil
        }
        guard active.id == id else { return nil }
        capture = nil
        return active.target
    }

    mutating func cancel(_ id: UUID) {
        if capture?.id == id { capture = nil }
    }
}

enum RemoteKeyboard {
    enum Result { case accepted, permissionDenied, unavailable, historyUnavailable, focusLost, revoked }

    struct DictationTarget {
        let application: NSRunningApplication
        let element: AXUIElement
    }

    private static let missionControl = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
    private static let browsers: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome", "org.mozilla.firefox",
        "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser", "com.vivaldi.Vivaldi",
    ]

    static func perform(_ packet: RemoteInputPacket, dictation: inout FocusedDictationSession<DictationTarget>,
                        stillAuthorized: () -> Bool) -> Result {
        guard stillAuthorized() else { return .revoked }
        switch packet {
        case .dictationCancel(let id):
            dictation.cancel(id)
            return .accepted
        case .dictationBegin(let id):
            dictation = FocusedDictationSession()
            guard AXIsProcessTrusted() else { return .permissionDenied }
            guard let target = focusedDictationTarget() else { return .unavailable }
            guard stillAuthorized() else { return .revoked }
            dictation.begin(id, target: target, now: ProcessInfo.processInfo.systemUptime)
            return .accepted
        case .dictationFinish(let id, let text):
            guard let target = dictation.take(id, now: ProcessInfo.processInfo.systemUptime)
            else { return .focusLost }
            return insertDictation(text, into: target, stillAuthorized: stillAuthorized)
        default:
            return perform(packet, stillAuthorized: stillAuthorized)
        }
    }

    static func perform(_ packet: RemoteInputPacket, stillAuthorized: () -> Bool) -> Result {
        guard stillAuthorized() else { return .revoked }
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { return .permissionDenied }
        switch packet {
        case .pair, .dictationBegin, .dictationFinish, .dictationCancel: return .unavailable
        case .browserBack: return navigateHistory("[", stillAuthorized: stillAuthorized)
        case .browserForward: return navigateHistory("]", stillAuthorized: stillAuthorized)
        case .spaceLeft: return SpacesNavigation.post(arrow: kVK_LeftArrow, stillAuthorized: stillAuthorized)
        case .spaceRight: return SpacesNavigation.post(arrow: kVK_RightArrow, stillAuthorized: stillAuthorized)
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

    private static func focusedDictationTarget() -> DictationTarget? {
        guard !IsSecureEventInputEnabled(),
              let application = NSWorkspace.shared.frontmostApplication else { return nil }

        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.3)
        guard let element = focusedElement(in: system), isEditable(element),
              isSettable(kAXSelectedTextAttribute, of: element) else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid > 0,
              application.processIdentifier == pid,
              let current = focusedElement(in: system), CFEqual(current, element),
              NSWorkspace.shared.frontmostApplication == application else { return nil }
        return DictationTarget(application: application, element: element)
    }

    private static func insertDictation(_ text: String, into target: DictationTarget,
                                       stillAuthorized: () -> Bool) -> Result {
        guard AXIsProcessTrusted() else { return .permissionDenied }
        guard let current = focusedDictationTarget(),
              current.application == target.application,
              !target.application.isTerminated,
              CFEqual(current.element, target.element) else { return .focusLost }
        guard stillAuthorized() else { return .revoked }

        // Insert through the captured AX element so a late focus switch cannot redirect the text.
        return AXUIElementSetAttributeValue(target.element, kAXSelectedTextAttribute as CFString, text as CFString)
            == .success ? .accepted : .unavailable
    }

    private static func isEditable(_ field: AXUIElement) -> Bool {
        guard let role = attribute(kAXRoleAttribute, of: field) as? String,
              [kAXTextFieldRole, kAXTextAreaRole].contains(role),
              (attribute(kAXSubroleAttribute, of: field) as? String) != kAXSecureTextFieldSubrole,
              (attribute(kAXEnabledAttribute, of: field) as? Bool) != false else { return false }
        return isSettable(kAXValueAttribute, of: field)
    }

    private static func typeText(_ text: String, stillAuthorized: () -> Bool) -> Result {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.3)
        guard let field = focusedElement(in: system),
              isEditable(field),
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
