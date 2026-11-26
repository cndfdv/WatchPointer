import AppKit

final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let live = Live()
    private var receiver: Receiver?
    private var notch: NotchController?
    private var statusItem: NSStatusItem?
    private let connectionItem = NSMenuItem()
    private let accessibilityItem = NSMenuItem()
    private let bluetoothItem = NSMenuItem()
    private let pairInputItem = NSMenuItem()
    private let forgetInputItem = NSMenuItem()
    private let smoothingMenu = NSMenu()
    private var smoothing = UserDefaults.standard.string(forKey: PointerSmoothing.preferenceKey)
        .flatMap(PointerSmoothing.init(rawValue:)) ?? .balanced

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        notch = NotchController(live: live)
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        if !AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary) {
            let app = Bundle.main.bundleURL.pathExtension == "app" ? "WatchPointer" : "your terminal app"
            print("Grant Accessibility access to \(app) in System Settings › Privacy & Security › Accessibility.")
        }
        receiver = Receiver(live: live, smoothing: smoothing)
    }

    func applicationWillTerminate(_ notification: Notification) {
        receiver?.stop()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        connectionItem.title = connectionTitle
        accessibilityItem.isHidden = AXIsProcessTrusted()
        bluetoothItem.isHidden = live.bluetoothStatus != .off && live.bluetoothStatus != .denied
        pairInputItem.isEnabled = live.bluetoothStatus == .ready
        forgetInputItem.isHidden = receiver?.watchInputPaired != true
    }

    private var connectionTitle: String {
        switch live.bluetoothStatus {
        case .starting: "Starting Bluetooth…"
        case .off: "Bluetooth is off"
        case .denied: "Bluetooth access is off"
        case .unavailable: "Bluetooth unavailable"
        case .ready:
            switch live.phase {
            case .waiting: "Waiting for Apple Watch"
            case .live: "Apple Watch connected"
            case .paused: "Apple Watch paused"
            case .idle: "Apple Watch disconnected"
            }
        }
    }

    private func installMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let button = item.button
        button?.image = NSImage(systemSymbolName: "applewatch", accessibilityDescription: nil)
        if button?.image == nil { button?.title = "WP" }
        button?.setAccessibilityLabel("WatchPointer")
        button?.toolTip = "WatchPointer"

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        connectionItem.isEnabled = false
        menu.addItem(connectionItem)

        accessibilityItem.title = "Open Accessibility Settings…"
        accessibilityItem.target = self
        accessibilityItem.action = #selector(openAccessibilitySettings)
        menu.addItem(accessibilityItem)

        bluetoothItem.title = "Open Bluetooth Settings…"
        bluetoothItem.target = self
        bluetoothItem.action = #selector(openBluetoothSettings)
        menu.addItem(bluetoothItem)

        menu.addItem(.separator())
        pairInputItem.title = "Pair Watch Input…"
        pairInputItem.target = self
        pairInputItem.action = #selector(pairWatchInput)
        menu.addItem(pairInputItem)

        forgetInputItem.title = "Forget Watch Input"
        forgetInputItem.target = self
        forgetInputItem.action = #selector(forgetWatchInput)
        menu.addItem(forgetInputItem)

        let smoothingItem = NSMenuItem(title: "Pointer Smoothing", action: nil, keyEquivalent: "")
        for mode in PointerSmoothing.allCases {
            let option = smoothingMenu.addItem(withTitle: mode.title, action: #selector(selectSmoothing(_:)),
                                               keyEquivalent: "")
            option.target = self
            option.representedObject = mode.rawValue
            option.state = mode == smoothing ? .on : .off
        }
        smoothingItem.submenu = smoothingMenu
        menu.addItem(smoothingItem)

        menu.addItem(.separator())
        let quitItem = menu.addItem(withTitle: "Quit WatchPointer", action: #selector(NSApplication.terminate(_:)),
                                    keyEquivalent: "q")
        quitItem.target = NSApplication.shared
        item.menu = menu
        statusItem = item
    }

    @objc private func openAccessibilitySettings() {
        openSettings("com.apple.preference.security?Privacy_Accessibility")
    }

    @objc private func openBluetoothSettings() {
        openSettings(live.bluetoothStatus == .denied
                     ? "com.apple.preference.security?Privacy_Bluetooth"
                     : "com.apple.BluetoothSettings")
    }

    @objc private func pairWatchInput() {
        guard let receiver else { return }
        let code = receiver.beginWatchInputPairing()
        let alert = NSAlert()
        alert.messageText = "Pair Watch Input"
        alert.informativeText = "On your Apple Watch, open Actions and choose Pair Watch Input. Enter the code below within two minutes."
        let label = NSTextField(labelWithString: code)
        label.font = .monospacedDigitSystemFont(ofSize: 26, weight: .semibold)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 0, width: 260, height: 38)
        alert.accessoryView = label
        alert.addButton(withTitle: "Close")
        NSApp.activate()
        alert.runModal()
    }

    @objc private func forgetWatchInput() {
        receiver?.forgetWatchInput()
    }

    @objc private func selectSmoothing(_ item: NSMenuItem) {
        guard let value = item.representedObject as? String,
              let selected = PointerSmoothing(rawValue: value) else { return }
        smoothing = selected
        UserDefaults.standard.set(selected.rawValue, forKey: PointerSmoothing.preferenceKey)
        receiver?.setPointerSmoothing(selected)
        for option in smoothingMenu.items {
            option.state = option == item ? .on : .off
        }
    }

    private func openSettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
