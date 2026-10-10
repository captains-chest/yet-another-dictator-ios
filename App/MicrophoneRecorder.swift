@preconcurrency import AVFoundation
import DictationCore
import Foundation

/// Microphone capture with AVAudioEngine, resampled to 16 kHz mono Float32.
///
/// Audio lives only in memory. While a session is armed the engine keeps running and the last
/// `preRollSeconds` are held, so the first syllable is kept and iOS leaves the process awake for
/// the keyboard. The orange microphone indicator stays visible for that whole session.
@MainActor
final class MicrophoneRecorder: AudioRecording {
    enum Failure: LocalizedError {
        case permissionDenied
        case session

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                "Microphone access is denied. Enable it in Settings."
            case .session:
                "The microphone couldn't be started."
            }
        }
    }

    /// Hard cap so a forgotten recording can't grow without bound (10 minutes).
    private static let maxSamples = Int(DictationController.sampleRate) * 60 * 10
    static let preRollSeconds = 0.4

    var onFailure: ((String) -> Void)?
    var onCapacityReached: (() -> Void)?
    private(set) var keepsReady = false

    private let buffer = CaptureBuffer(
        capacity: maxSamples,
        preRoll: Int(DictationController.sampleRate * preRollSeconds)
    )
    private var interruptionObserver: (any NSObjectProtocol)?
    private lazy var host: AudioEngineHost = {
        buffer.onCapacityReached = { [weak self] in
            Task { @MainActor in self?.onCapacityReached?() }
        }
        return AudioEngineHost(buffer: buffer) { [weak self] message in
            Task { @MainActor in self?.onFailure?(message) }
        }
    }()

    init() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            MainActor.assumeIsolated {
                self?.handleInterruption(typeRaw: typeRaw, optionsRaw: optionsRaw)
            }
        }
    }

    func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
        try session.setActive(true)
    }

    func deactivateSession() {
        setKeepsReady(false)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func prepare() {
        guard AVAudioApplication.shared.recordPermission == .granted else { return }
        host.prepare()
    }

    /// Keeps the engine running between dictations. Required while a session is armed, so the app
    /// is still awake when the keyboard asks to record.
    func setKeepsReady(_ on: Bool) {
        keepsReady = on
        guard AVAudioApplication.shared.recordPermission == .granted else { return }
        if on {
            host.run()
        } else if !buffer.isCapturing {
            host.idle()
        }
    }

    func start(onLevel: @escaping @Sendable (Float) -> Void) throws {
        guard AVAudioApplication.shared.recordPermission != .denied else { throw Failure.permissionDenied }
        buffer.begin(onLevel: onLevel)
        host.run()
    }

    func stop() -> [Float] {
        let samples = buffer.end()
        if !keepsReady { host.idle() }
        return samples
    }

    private func handleInterruption(typeRaw: UInt?, optionsRaw: UInt) {
        guard let typeRaw, let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        switch type {
        case .began:
            let wasCapturing = buffer.isCapturing
            host.idle()
            if wasCapturing { onFailure?("Recording was interrupted.") }
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            guard options.contains(.shouldResume), keepsReady else { return }
            try? activateSession()
            host.run()
        @unknown default:
            break
        }
    }
}

/// Owns the AVAudioEngine. All of its state is touched only on `queue`.
private final class AudioEngineHost: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.captainduckay.dictator.ios.audio", qos: .userInitiated)
    private let buffer: CaptureBuffer
    private let onFailure: @Sendable (String) -> Void
    private var engine: AVAudioEngine?
    private var configurationObserver: (any NSObjectProtocol)?
    private var wantsRunning = false
    private var rebuildPending = false

    init(buffer: CaptureBuffer, onFailure: @escaping @Sendable (String) -> Void) {
        self.buffer = buffer
        self.onFailure = onFailure
    }

    func prepare() {
        queue.async { [self] in
            if engine == nil { try? build() }
        }
    }

    func run() {
        queue.async { [self] in
            wantsRunning = true
            startIfNeeded()
        }
    }

    func idle() {
        queue.async { [self] in
            wantsRunning = false
            engine?.stop()
            buffer.clearPreRoll()
        }
    }

    private func startIfNeeded() {
        do {
            if engine == nil { try build() }
            guard let engine, !engine.isRunning else { return }
            try engine.start()
        } catch {
            teardown()
            wantsRunning = false
            onFailure("Could not start microphone: \(error.localizedDescription)")
        }
    }

    private func build() throws {
        teardown()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw Failure.noInput }
        guard
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: DictationController.sampleRate,
                channels: 1,
                interleaved: false
            ),
            let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        else { throw Failure.converterUnavailable }

        input.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: inputFormat,
            block: Self.makeTap(converter: converter, outputFormat: outputFormat, buffer: buffer)
        )
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.queue.async { self.scheduleRebuild() }
        }
        engine.prepare()
        self.engine = engine
    }

    private func scheduleRebuild() {
        guard !rebuildPending else { return }
        rebuildPending = true
        queue.asyncAfter(deadline: .now() + 0.25) { [self] in
            rebuildPending = false
            rebuild()
        }
    }

    private func rebuild() {
        teardown()
        if wantsRunning {
            startIfNeeded()
        } else {
            try? build()
        }
    }

    private func teardown() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        buffer.clearPreRoll()
    }

    private enum Failure: LocalizedError {
        case noInput, converterUnavailable
        var errorDescription: String? {
            switch self {
            case .noInput: "No microphone input is available."
            case .converterUnavailable: "Cannot convert microphone audio to 16 kHz."
            }
        }
    }

    /// Built outside any actor: the tap runs on a realtime audio thread.
    private static func makeTap(
        converter: AVAudioConverter,
        outputFormat: AVAudioFormat,
        buffer store: CaptureBuffer
    ) -> AVAudioNodeTapBlock {
        let ratio = outputFormat.sampleRate / converter.inputFormat.sampleRate
        return { buffer, _ in
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
            guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
            var consumed = false
            var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, let channel = output.floatChannelData?[0] else { return }
            store.append(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
        }
    }
}
