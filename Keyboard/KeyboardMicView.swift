import DictatorIOS
import SwiftUI
import UIKit

struct KeyboardMicView: View {
    @Bindable var screen: KeyboardScreen
    var onSwitch: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: onSwitch) {
                    Image(systemName: "globe")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Next keyboard")
                Spacer()
                if screen.fullAccess, let session = screen.session, session.canUndo {
                    Button {
                        Task { await session.undo() }
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(.body)
                            .frame(height: 44)
                            .padding(.horizontal, 8)
                    }
                    .accessibilityLabel("Undo last dictation")
                    .accessibilityHint("Deletes the text the last dictation typed.")
                }
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 0)

            if !screen.fullAccess || screen.session == nil {
                explanation(
                    "Turn on Allow Full Access for this keyboard so it can receive the transcript from Dictator. The keyboard does not use the network, and nothing you type is stored."
                )
            } else if let session = screen.session {
                content(session)
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    @ViewBuilder
    private func content(_ session: KeyboardSession) -> some View {
        switch session.phase {
        case .hostUnavailable:
            explanation("Open Dictator and turn on Keep dictation available. The microphone indicator stays on while a session is armed. Audio is not saved.")
        case .loadingModel:
            ProgressView("Loading the speech model…")
        case .unavailable(let message):
            explanation(message)
        case .ready, .recording, .transcribing:
            mic(session)
            if let banner = session.banner {
                Text(banner)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }

    private func mic(_ session: KeyboardSession) -> some View {
        VStack(spacing: 8) {
            Circle()
                .fill(color(session.phase))
                .frame(width: KeyboardMetrics.buttonSize, height: KeyboardMetrics.buttonSize)
                .overlay {
                    Image(systemName: session.phase == .transcribing ? "ellipsis" : "mic.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                }
                .overlay {
                    PressCatcher(
                        enabled: session.canDictate,
                        onPress: { session.press() },
                        onRelease: { session.release() }
                    )
                }
                .opacity(session.canDictate || session.phase == .transcribing ? 1 : 0.4)
                .accessibilityHidden(true)
            Text(caption(session.phase))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func color(_ phase: KeyboardPhase) -> Color {
        switch phase {
        case .recording: .red
        case .transcribing: .orange
        default: .accentColor
        }
    }

    private func caption(_ phase: KeyboardPhase) -> String {
        switch phase {
        case .recording: "Release to finish, or tap again"
        case .transcribing: "Transcribing…"
        default: "Tap to toggle · Hold to talk"
        }
    }

    private func explanation(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
    }
}

/// Touch handling that survives the button redrawing when recording starts.
private struct PressCatcher: UIViewRepresentable {
    var enabled: Bool
    var onPress: () -> Void
    var onRelease: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = true
        view.accessibilityLabel = "Dictate"
        view.accessibilityHint = "Tap to start and stop. Hold to talk, then release."
        let recognizer = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.pressed(_:))
        )
        recognizer.minimumPressDuration = 0
        recognizer.cancelsTouchesInView = false
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.enabled = enabled
        context.coordinator.onPress = onPress
        context.coordinator.onRelease = onRelease
        uiView.accessibilityTraits = enabled ? [.button] : [.button, .notEnabled]
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(enabled: enabled, onPress: onPress, onRelease: onRelease)
    }

    final class Coordinator: NSObject {
        var enabled: Bool
        var onPress: () -> Void
        var onRelease: () -> Void
        private var down = false

        init(enabled: Bool, onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
            self.enabled = enabled
            self.onPress = onPress
            self.onRelease = onRelease
        }

        @objc func pressed(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began:
                guard enabled, !down else { return }
                down = true
                onPress()
            case .ended, .cancelled, .failed:
                guard down else { return }
                down = false
                onRelease()
            default:
                break
            }
        }
    }
}
