import SwiftUI

struct InputFeedback: Equatable {
    private let id = UUID()
    let message: String
    let succeeded: Bool

    init(_ result: Result<Void, WatchInputError>, success: String) {
        switch result {
        case .success:
            message = success
            succeeded = true
        case let .failure(error):
            message = error.message
            succeeded = false
        }
    }
}

struct RemoteActionsView: View {
    @ObservedObject var pointer: Pointer
    @Binding var draft: String
    @Binding var feedback: InputFeedback?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let feedback {
                        Text(feedback.message)
                            .font(.footnote)
                            .foregroundStyle(feedback.succeeded ? .green : .orange)
                    }
                    if !pointer.connected {
                        Text("Waiting for the Mac")
                            .foregroundStyle(.secondary)
                    } else if !pointer.supportsRemoteInput {
                        Text("Remote input is unavailable on this Mac.")
                            .foregroundStyle(.secondary)
                    }

                    if pointer.connected {
                        Text("Swipe up or down with one finger to scroll.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if pointer.supportsRemoteInput {
                        Text("On the pad, swipe sideways with one finger for tabs or two fingers for Spaces. Swipe up with two fingers for Mission Control.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    TextFieldLink(prompt: Text("Dictate or enter text")) {
                        Label(draft.isEmpty ? "Dictate" : "Replace draft", systemImage: "mic")
                    } onSubmit: { text in
                        draft = text
                        feedback = nil
                    }
                    .disabled(pointer.remoteInputBusy)

                    if !draft.isEmpty {
                        Text(draft)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityLabel("Draft")
                            .accessibilityValue(draft)

                        Text("Focus a text field on the Mac before sending.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if pointer.supportsRemoteInput, draft.utf8.count > pointer.dictationByteLimit {
                            Text("The draft exceeds the \(pointer.dictationByteLimit)-byte limit.")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }

                        Button("Send") {
                            let text = draft
                            pointer.sendDictation(text) { result in
                                if case .success = result, draft == text { draft = "" }
                                feedback = InputFeedback(result, success: "Text sent")
                            }
                        }
                        .disabled(!canSend)
                    }

                    if pointer.supportsRemoteInput {
                        TextFieldLink(prompt: Text("Six-digit code")) {
                            Label("Pair Watch Input", systemImage: "key")
                        } onSubmit: { code in
                            pointer.pairRemoteInput(code: code.trimmingCharacters(in: .whitespacesAndNewlines)) { result in
                                feedback = InputFeedback(result, success: "Watch input paired")
                            }
                        }
                        .disabled(pointer.remoteInputBusy)
                        Text("On the Mac, choose Pair Watch Input… from the WatchPointer menu.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 5)
            }
            .navigationTitle("Remote actions")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var canSend: Bool {
        pointer.connected && pointer.supportsRemoteInput && !pointer.remoteInputBusy
            && draft.utf8.count <= pointer.dictationByteLimit
    }
}
