import AVFoundation
import DictatorIOS
import Foundation
import Observation
import OSLog
import SwiftUI
import ParakeetTranscription
import SpeechModels
import UIKit
import WhisperTranscription

/// Composition root: microphone, the downloaded model, and the keyboard hand-off.
@MainActor
@Observable
final class AppModel {
    let controller: DictationController
    /// Opt-in download of the chosen model (ADR 0004, ADR 0005).
    let modelDownload: ModelDownload
    /// The model the user chose; nil until they pick one in the first-launch picker.
    private(set) var chosenModel: SpeechModel?
    /// Shown at launch only while no model is chosen.
    var showsModelPicker = false
    @ObservationIgnored private let modelChoice = ModelChoice(defaults: .standard)
    @ObservationIgnored private let engine: ActiveTranscriber
    var language: DictationLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Self.languageKey)
            controller.language = language
        }
    }

    /// True while the app is holding the microphone open for the keyboard.
    private(set) var sessionArmed = false
    private(set) var microphone: MicrophonePermission = .undetermined
    /// Setup and retry problems. Never a transcript.
    private(set) var setupError: String?
    private(set) var retrying = false

    @ObservationIgnored private let recorder: MicrophoneRecorder
    @ObservationIgnored private let mailbox: SessionMailbox?
    @ObservationIgnored private let host: SessionHost?
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var watch: Task<Void, Never>?
    @ObservationIgnored private static let sessionArmedKey = "sessionArmed"
    @ObservationIgnored private static let languageKey = "language"
    @ObservationIgnored private static let log = Logger(subsystem: "com.captainduckay.dictator.ios", category: "state")

    /// How long a retry waits for the keyboard to come up in a text field.
    private static let retryTimeout: Duration = .seconds(120)

    init() {
        let modelDownload = ModelDownload()
        self.modelDownload = modelDownload
        let recorder = MicrophoneRecorder()
        let engine = ActiveTranscriber()
        self.engine = engine
        let transcriber = engine
        let mailbox = AppGroup.containerURL().flatMap { try? SessionMailbox(directory: $0) }
        let controller: DictationController
        let host: SessionHost?
        if let mailbox {
            let handoff = HandoffInserter(mailbox: mailbox)
            let made = DictationController(
                recorder: recorder,
                transcriber: transcriber,
                inserter: handoff,
                precedingText: NoPrecedingText()
            )
            controller = made
            host = SessionHost(controller: made, inserter: handoff, mailbox: mailbox)
        } else {
            controller = DictationController(
                recorder: recorder,
                transcriber: transcriber,
                inserter: UnavailableInserter(),
                precedingText: NoPrecedingText()
            )
            host = nil
        }
        self.recorder = recorder
        self.mailbox = mailbox
        self.controller = controller
        self.host = host
        language = DictationLanguage(storedValue: defaults.string(forKey: Self.languageKey))
        controller.language = language

        let log = Self.log
        controller.onStateChange = { [weak self] state in
            log.notice("state: \(String(describing: state), privacy: .public)")
            self?.host?.publish()
        }
        controller.onTiming = { timing in
            log.notice("dictation: \(timing.audioSeconds, format: .fixed(precision: 1), privacy: .public) s audio, release→typed \(timing.releaseToTypedSeconds, format: .fixed(precision: 2), privacy: .public) s, transcription \(timing.transcriptionSeconds, format: .fixed(precision: 2), privacy: .public) s")
        }
        recorder.onFailure = { [weak self] message in
            log.error("microphone: \(message, privacy: .public)")
            self?.controller.recordingFailed(message)
        }
        recorder.onCapacityReached = { [weak self] in
            self?.controller.recordingReachedLimit()
        }

        let saved = defaults.bool(forKey: Self.sessionArmedKey)
        modelDownload.onReady = { [weak self] in await self?.controller.loadModel() }
        Task {
            refreshMicrophone()
            // Nothing downloads here: with no choice the picker is shown, otherwise the chosen
            // model is used if it's on disk and waits for the user's Download tap if not.
            switch ModelStartup.decide(choice: modelChoice.selected, installed: modelDownload.installedModels) {
            case .showPicker:
                showsModelPicker = true
            case .use(let model):
                if modelChoice.selected == nil { modelChoice.choose(model) }
                await use(model)
            }
            // Without the model this reports "not downloaded yet" to the app and the keyboard.
            await controller.loadModel()
            modelDownload.resumeIfStarted()
            if saved { await setSessionArmed(true) }
        }
    }

    /// Persists the choice and switches to that model. Downloading it still needs the user's tap.
    func chooseModel(_ model: SpeechModel) async {
        guard !modelDownload.isBusy else { return }
        modelChoice.choose(model)
        showsModelPicker = false
        await use(model)
        await controller.loadModel()
    }

    private func use(_ model: SpeechModel) async {
        chosenModel = model
        modelDownload.select(model)
        let folder = modelDownload.folder
        let transcriber: any Transcribing = switch model {
        case .parakeetV2: ParakeetTranscriber(modelFolder: folder)
        case .whisperSmall: WhisperKitTranscriber(modelFolder: folder)
        }
        await engine.use(transcriber)
    }

    func refreshMicrophone() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: microphone = .granted
        case .denied: microphone = .denied
        case .undetermined: microphone = .undetermined
        @unknown default: microphone = .denied
        }
    }

    @discardableResult
    func requestMicrophone() async -> Bool {
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        refreshMicrophone()
        return granted
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func setSessionArmed(_ on: Bool) async {
        guard let host else {
            sessionArmed = false
            setupError = "The shared container isn't available, so the keyboard can't reach this app."
            return
        }
        if !on {
            watch?.cancel()
            watch = nil
            recorder.deactivateSession()
            host.disarm()
            sessionArmed = false
            defaults.set(false, forKey: Self.sessionArmedKey)
            setupError = nil
            return
        }
        if microphone != .granted {
            if microphone == .undetermined { _ = await requestMicrophone() }
            guard microphone == .granted else {
                sessionArmed = false
                defaults.set(false, forKey: Self.sessionArmedKey)
                setupError = "Dictator needs the microphone before a session can stay available."
                return
            }
        }
        do {
            try recorder.activateSession()
        } catch {
            sessionArmed = false
            defaults.set(false, forKey: Self.sessionArmedKey)
            setupError = error.localizedDescription
            return
        }
        recorder.prepare()
        recorder.setKeepsReady(true)
        host.arm()
        startWatching()
        sessionArmed = true
        defaults.set(true, forKey: Self.sessionArmedKey)
        setupError = nil
    }

    func retryUndelivered() async {
        guard let text = controller.undeliveredTranscript, let mailbox else { return }
        guard sessionArmed else {
            setupError = "Turn on Keep dictation available, then open the keyboard in a text field."
            return
        }
        retrying = true
        defer { retrying = false }
        let delivery = DictationDelivery(
            id: UUID(),
            commandID: UUID(),
            text: text,
            deleteCount: nil,
            acceptsWithoutCommand: true,
            createdAt: Date().timeIntervalSince1970
        )
        do {
            try mailbox.writeDelivery(delivery)
        } catch {
            setupError = error.localizedDescription
            return
        }
        SessionSignal.delivery.post()
        let deadline = ContinuousClock.now + Self.retryTimeout
        while ContinuousClock.now < deadline {
            if let ack = mailbox.takeAck(id: delivery.id) {
                switch ack.result {
                case .inserted:
                    controller.discardUndelivered()
                    setupError = nil
                case .failed:
                    setupError = ack.message ?? "The keyboard couldn't type the dictation."
                }
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        mailbox.removeDelivery(id: delivery.id)
        setupError = "Open the Dictator keyboard in a text field, then try again."
    }

    func discardUndelivered() {
        controller.discardUndelivered()
        mailbox?.discardDelivery()
    }

    private func startWatching() {
        watch?.cancel()
        DarwinSessionCenter.shared.observe(.command) { [weak self] in
            Task { @MainActor in self?.host?.drainCommands() }
        }
        watch = Task { [weak self] in
            while !Task.isCancelled {
                self?.host?.publish()
                self?.host?.drainCommands()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

enum MicrophonePermission: Equatable {
    case granted, denied, undetermined
}

/// Used only when the App Group container is missing, so the model can still load and the screen
/// can explain that the keyboard is unreachable.
@MainActor
private final class UnavailableInserter: TextInserting {
    func preflight() throws {}
    func insert(_ text: String) async throws { throw Failure.unreachable }
    func deleteBackward(_ count: Int) async throws { throw Failure.unreachable }

    enum Failure: LocalizedError {
        case unreachable
        var errorDescription: String? { "The keyboard isn't connected." }
    }
}
