import SwiftUI

/// Receiver state for the menu and notch panel. Updated on the main thread.
final class Live: ObservableObject {
    enum Phase { case waiting, live, paused, idle }
    enum Toast { case connected, lost, centered, paused, resumed }
    enum BluetoothStatus { case starting, ready, off, denied, unavailable }

    @Published var phase = Phase.waiting
    var bluetoothStatus = BluetoothStatus.starting
    @Published var toast: Toast?
    @Published var hovered = false
    @Published var pointer = CGPoint(x: 0.5, y: 0.5) // 0...1 across the main display
    @Published var aimLeft = 0.0                     // degrees
    @Published var aimUp = 0.0
    @Published var rate = 0                          // samples per second from the watch
    @Published var clicks = 0
    @Published var watch: WatchInfo?
    /// Keep the panel open without hovering. Remembered between runs.
    @Published var pinned = UserDefaults.standard.bool(forKey: "pinned") {
        didSet { UserDefaults.standard.set(pinned, forKey: "pinned") }
    }

    private var clearToast: DispatchWorkItem?

    func show(_ toast: Toast) {
        self.toast = toast
        clearToast?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        clearToast = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }
}
