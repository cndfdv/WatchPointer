import SwiftUI

/// Mac scroll distance, in pixels, per unit of Crown turn. Higher = faster scrolling.
private let crownPixels = 100.0

/// A remote you use without looking: one big pad, three buttons in fixed places, haptics for feedback.
struct ContentView: View {
    @StateObject private var pointer = Pointer()
    @State private var crown = 0.0
    @FocusState private var crownFocused: Bool
    @State private var clicks = 0
    @State private var centers = 0
    @State private var confirmUnpair = false
    @State private var unpairTitle = ""
    @State private var showActions = false
    @State private var draft = ""
    @State private var feedback: InputFeedback?

    var body: some View {
        NavigationStack {
            remote
                .toolbar {
                    if pointer.connected || !draft.isEmpty {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showActions = true
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .accessibilityLabel("Remote actions")
                        }
                    }
                    if pointer.connected {
                        // Top-left, next to the clock: which Mac this is, and the way to unpair it.
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                unpairTitle = pointer.pairedName ?? "Mac" // fixed while the dialog is up
                                confirmUnpair = true
                            } label: { Image(systemName: "laptopcomputer") }
                        }
                    }
                }
                .sheet(isPresented: $showActions, onDismiss: { crownFocused = true }) {
                    RemoteActionsView(pointer: pointer, draft: $draft, feedback: $feedback)
                }
                .confirmationDialog(unpairTitle, isPresented: $confirmUnpair, titleVisibility: .visible) {
                    Button("Unpair", role: .destructive) {
                        // Unpair once the dialog has closed; changing the screen under it made it pop up a second time.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { pointer.forget() }
                    }
                }
        }
    }

    private var remote: some View {
        Group {
            if pointer.connected {
                VStack(spacing: 6) {
                    ClickPad(paused: pointer.paused, clicks: $clicks, pointer: pointer, swipe: sendSwipe)
                        .frame(maxHeight: .infinity)
                        .overlay(alignment: .bottom) {
                            if let feedback, !showActions {
                                Text(feedback.message)
                                    .font(.footnote)
                                    .multilineTextAlignment(.center)
                                    .padding(6)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                                    .padding(4)
                                    .allowsHitTesting(false)
                            }
                        }
                    HStack(spacing: 6) {
                        PadButton(symbol: "contextualmenu.and.cursorarrow") {
                            clicks += 1
                            // Buttons fire on release; a press lasts about this long, so this is roughly touch-down.
                            pointer.send(.rightClick, at: ProcessInfo.processInfo.systemUptime - 0.12)
                        }
                        PadButton(symbol: "scope") {
                            centers += 1
                            pointer.center()
                        }
                        PadButton(symbol: pointer.paused ? "play.fill" : "pause.fill", tint: pointer.paused ? .orange : .white) {
                            pointer.togglePause()
                        }
                    }
                    .frame(height: 52)
                }
                .padding(.horizontal, 4)
                .transition(.opacity)
            } else if let name = pointer.pairedName {
                WaitingForMac(name: name) { pointer.forget() }
                    .transition(.opacity)
            } else {
                PairList(found: pointer.found) { pointer.pair($0) }
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .animation(.smooth(duration: 0.3), value: pointer.connected)
        // The Crown only reaches the focused view, so keep focus here rather than on a button.
        .focusable()
        .focused($crownFocused)
        .digitalCrownRotation($crown)
        .onChange(of: crown) { old, new in pointer.scroll(by: (new - old) * crownPixels) }
        .onAppear { crownFocused = true }
        .onChange(of: pointer.connected) { crownFocused = true }
        .sensoryFeedback(.impact(weight: .light), trigger: clicks)
        .sensoryFeedback(.success, trigger: centers)
        .sensoryFeedback(.selection, trigger: pointer.paused)
        .sensoryFeedback(trigger: pointer.connected) { _, now in now ? .start : .stop }
        .sensoryFeedback(trigger: feedback) { _, value in
            guard let value else { return nil }
            return value.succeeded ? .success : .error
        }
        .task(id: showActions ? nil : feedback) {
            guard let feedback, !showActions else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, !showActions, self.feedback == feedback else { return }
            self.feedback = nil
        }
    }

    private func sendSwipe(_ command: WatchInputCommand) {
        let message = switch command {
        case .browserTabPrevious: "Previous tab"
        case .browserTabNext: "Next tab"
        case .spaceLeft: "Previous Space"
        case .spaceRight: "Next Space"
        case .missionControl: "Mission Control"
        }
        pointer.sendSwipe(command) { result in
            feedback = InputFeedback(result, success: message)
        }
    }
}

/// Not paired yet: every Mac running the receiver nearby, each with a Pair button.
private struct PairList: View {
    let found: [FoundMac]
    let pair: (FoundMac) -> Void

    var body: some View {
        if found.isEmpty {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse)
        } else {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(found) { mac in
                        Button { pair(mac) } label: {
                            HStack(spacing: 8) {
                                Text(mac.name)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("Pair")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(.white, in: Capsule())
                            }
                            .font(.system(size: 15, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(minHeight: 52)
                            .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
}

/// Paired, but that Mac isn't connected right now (receiver closed or out of range). Connects by itself when it's back.
private struct WaitingForMac: View {
    let name: String
    let forget: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "laptopcomputer")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse)
            Text(name)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(white: 0.6))
                .lineLimit(1)
            Spacer()
            Button(action: forget) {
                Text("Forget")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressStyle())
        }
        .padding(.horizontal, 4)
    }
}

/// Tap = click. Hold = grab (mouse down); point to move; let go to drop.
private struct ClickPad: View {
    let paused: Bool
    @Binding var clicks: Int
    let pointer: Pointer
    let swipe: (WatchInputCommand) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @GestureState private var gestureActive = false
    @State private var pressing = false
    @State private var tracker = PadGesture<SpatialEventCollection.Event.ID>()
    @State private var holdTimer: Timer?
    @State private var touchDown: TimeInterval = 0

    private var dragging: Bool { tracker.dragging }

    private var fill: Color {
        if dragging { return .white }
        if paused { return Color.orange.opacity(0.25) }
        return Color(white: pressing ? 0.28 : 0.16)
    }

    private var symbol: String { dragging ? "hand.raised.fill" : paused ? "pause.fill" : "cursorarrow.click" }

    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(fill)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(dragging ? .black : paused ? .orange : Color(white: 0.55))
                    .contentTransition(.symbolEffect(.replace))
            }
            .scaleEffect(pressing && !dragging ? 0.98 : 1)
            .animation(.smooth(duration: 0.15), value: pressing)
            .animation(.smooth(duration: 0.2), value: dragging)
            .contentShape(Rectangle())
            .gesture(
                SpatialEventGesture()
                    .updating($gestureActive) { _, active, _ in active = true }
                    .onChanged { update($0) }
                    .onEnded {
                        update($0, ending: true)
                        if pressing { complete(tracker.finish()) }
                    }
            )
            .onChange(of: gestureActive) { _, active in
                if !active { cancel() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { cancel() }
            }
            .onDisappear { cancel() }
            .sensoryFeedback(trigger: dragging) { _, now in .impact(weight: now ? .heavy : .light) }
    }

    private func update(_ events: SpatialEventCollection, ending: Bool = false) {
        let touches = events.filter { $0.kind == .touch }
        let active = touches.filter { $0.phase == .active }
        if !pressing, !ending, !active.isEmpty {
            pressing = true
            touchDown = ProcessInfo.processInfo.systemUptime // same clock as the motion samples
            holdTimer = Timer.scheduledTimer(withTimeInterval: holdToDrag, repeats: false) { _ in
                if tracker.beginHold() { pointer.send(.drag, 1, at: touchDown) }
            }
        }
        guard pressing else { return }
        for touch in touches {
            tracker.record(touch.id, at: touch.location, active: touch.phase == .active)
        }
        if active.count > 1 {
            tracker.recordOverlap()
            if dragging {
                perform(tracker.cancel())
            }
        }
        if touches.contains(where: { $0.phase == .cancelled }) {
            perform(tracker.cancel())
        }
        if !tracker.canHold || active.isEmpty {
            holdTimer?.invalidate()
        }
    }

    private func cancel() {
        if pressing { complete(tracker.cancel()) }
    }

    private func complete(_ outcome: PadGesture<SpatialEventCollection.Event.ID>.Outcome?) {
        holdTimer?.invalidate()
        holdTimer = nil
        pressing = false
        tracker = PadGesture()
        perform(outcome)
    }

    private func perform(_ outcome: PadGesture<SpatialEventCollection.Event.ID>.Outcome?) {
        switch outcome {
        case .click:
            clicks += 1
            pointer.send(.leftClick, at: touchDown)
        case .drop:
            pointer.send(.drag, 0, at: ProcessInfo.processInfo.systemUptime - 0.05)
        case let .swipe(command):
            swipe(command)
        case nil:
            break
        }
    }
}

private struct PadButton: View {
    let symbol: String
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.16))
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(tint)
                        .contentTransition(.symbolEffect(.replace))
                }
        }
        .buttonStyle(PressStyle())
    }
}

private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.smooth(duration: 0.12), value: configuration.isPressed)
    }
}
