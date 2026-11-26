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
func selectedFixtureTab() -> Int? {
    guard let value = attribute(kAXFocusedWindowAttribute, of: application),
          CFGetTypeID(value) == AXUIElementGetTypeID(),
          let title = attribute(kAXTitleAttribute, of: value as! AXUIElement) as? String
    else { return nil }
    return (1...3).first { title.hasPrefix("WatchPointer Tab Fixture · Tab \($0)") }
}

func send(_ direction: RemoteInputPacket, on tab: Int) -> RemoteKeyboard.Result {
    guard NSWorkspace.shared.frontmostApplication == chrome, selectedFixtureTab() == tab
    else { fatalError("Chrome lost focus or the active tab is not the expected fixture tab.") }
    return RemoteKeyboard.perform(direction, stillAuthorized: { true })
}

guard selectedFixtureTab() == 2 else {
    fatalError("Open the three fixture tabs and select Tab 2 before running this test.")
}
_ = chrome.activate(options: [])
precondition(waitUntil { NSWorkspace.shared.frontmostApplication == chrome && selectedFixtureTab() == 2 })
precondition(RemoteKeyboard.perform(.browserTabNext, stillAuthorized: { false }) == .revoked)

precondition(send(.browserTabPrevious, on: 2) == .accepted)
precondition(waitUntil { selectedFixtureTab() == 1 })
precondition(send(.browserTabNext, on: 1) == .accepted)
precondition(waitUntil { selectedFixtureTab() == 2 })
precondition(send(.browserTabNext, on: 2) == .accepted)
precondition(waitUntil { selectedFixtureTab() == 3 })
precondition(send(.browserTabPrevious, on: 3) == .accepted)
precondition(waitUntil { selectedFixtureTab() == 2 })
precondition(send(.browserTabPrevious, on: 2) == .accepted)
precondition(waitUntil { selectedFixtureTab() == 1 })
print("Chrome tab switching acceptance passed.")
