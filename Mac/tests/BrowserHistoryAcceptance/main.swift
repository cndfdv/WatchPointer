import AppKit
import ApplicationServices

func attribute(_ key: String, of element: AXUIElement) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
}

func waitUntil(_ predicate: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(4)
    while !predicate(), Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    return predicate()
}

guard AXIsProcessTrusted(), CGPreflightPostEventAccess(),
      let chrome = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first
else { fatalError("The test requires Chrome and Accessibility access.") }

let application = AXUIElementCreateApplication(chrome.processIdentifier)
func selectedPage() -> Int? {
    guard let value = attribute(kAXFocusedWindowAttribute, of: application),
          CFGetTypeID(value) == AXUIElementGetTypeID(),
          let title = attribute(kAXTitleAttribute, of: value as! AXUIElement) as? String
    else { return nil }
    return (1...2).first { title.hasPrefix("Проверка WatchPointer · Страница \($0)") }
}

func send(_ direction: RemoteInputPacket, on page: Int) -> RemoteKeyboard.Result {
    guard NSWorkspace.shared.frontmostApplication == chrome, selectedPage() == page
    else { fatalError("Chrome lost focus or the test tab changed.") }
    return RemoteKeyboard.perform(direction, stillAuthorized: { true })
}

guard selectedPage() != nil else { fatalError("Select the history fixture in Chrome.") }
_ = chrome.activate(options: [])
precondition(waitUntil { NSWorkspace.shared.frontmostApplication == chrome })
if selectedPage() == 2 {
    precondition(send(.browserBack, on: 2) == .accepted)
}
precondition(waitUntil { selectedPage() == 1 })
precondition(waitUntil { send(.browserBack, on: 1) == .historyUnavailable })
precondition(RemoteKeyboard.perform(.browserForward, stillAuthorized: { false }) == .revoked)
precondition(send(.browserForward, on: 1) == .accepted)
precondition(waitUntil { selectedPage() == 2 })
precondition(waitUntil { send(.browserForward, on: 2) == .historyUnavailable })
precondition(send(.browserBack, on: 2) == .accepted)
precondition(waitUntil { selectedPage() == 1 })
print("Chrome history acceptance passed.")
