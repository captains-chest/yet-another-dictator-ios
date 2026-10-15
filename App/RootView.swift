import DictationCore
import SpeechModels
import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                sessionSection
                microphoneSection
                languageSection
                keyboardSection
                modelSection
                if let text = model.controller.undeliveredTranscript {
                    undeliveredSection(text)
                }
            }
            .navigationTitle("Dictator")
            .onAppear { model.refreshMicrophone() }
            .sheet(isPresented: $model.showsModelPicker) {
                ModelPickerSheet(download: model.modelDownload) { choice in
                    Task { await model.chooseModel(choice) }
                }
            }
        }
    }

    private var sessionSection: some View {
        Section {
            Toggle("Keep dictation available", isOn: Binding(
                get: { model.sessionArmed },
                set: { on in Task { await model.setSessionArmed(on) } }
            ))
            Text("While this is on, Dictator stays awake in the background and the microphone indicator stays visible. Audio is kept only for the current dictation and is never saved.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            statusLine
            if let setupError = model.setupError {
                Text(setupError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Session")
        }
    }

    private var statusLine: some View {
        let label: String = switch model.controller.state {
        case .loadingModel: "Loading the speech model…"
        case .ready: model.sessionArmed ? "Ready" : "Off"
        case .recording: "Recording"
        case .transcribing: "Transcribing"
        case .unavailable: "Unavailable"
        }
        return Text(label)
            .font(.footnote)
    }

    private var microphoneSection: some View {
        Section {
            switch model.microphone {
            case .granted:
                Text("Microphone allowed")
            case .undetermined:
                Button("Allow Microphone") { Task { await model.requestMicrophone() } }
            case .denied:
                Button("Open Settings") { model.openSettings() }
            }
            Text("Dictator listens only while you dictate, and transcribes on this iPhone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Microphone")
        }
    }

    private var languageSection: some View {
        Section {
            Picker("Language", selection: $model.language) {
                ForEach(DictationLanguage.allCases, id: \.self) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .disabled(model.chosenModel?.isEnglishOnly == true)
            if model.chosenModel?.isEnglishOnly == true {
                Text("Parakeet understands English only. Switch to Whisper Small to choose Automatic or English.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Language")
        }
    }

    private var keyboardSection: some View {
        Section {
            Text("Add the keyboard in Settings → General → Keyboard → Keyboards → Add New Keyboard → Dictator.")
            Text("Turn on Allow Full Access. That lets the keyboard read the transcript from this app. The keyboard does not use the network, and nothing you type is stored.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Keyboard")
        }
    }

    @ViewBuilder private var modelSection: some View {
        Section {
            ModelSection(download: model.modelDownload, state: model.controller.state, chosen: model.chosenModel)
        } header: {
            Text("Model")
        }
        Section {
            ModelList(download: model.modelDownload, chosen: model.chosenModel) { choice in
                Task { await model.chooseModel(choice) }
            }
        } header: {
            Text("Models")
        }
    }

    private func undeliveredSection(_ text: String) -> some View {
        Section {
            Text(text)
            Text("Open a text field, switch to the Dictator keyboard, and try again. It is typed there, not copied.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Try again") { Task { await model.retryUndelivered() } }
                .disabled(model.retrying)
            Button("Discard", role: .destructive) { model.discardUndelivered() }
        } header: {
            Text("Not typed")
        }
    }
}
