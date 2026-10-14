import Foundation
import Network
import Observation
import OSLog
import SpeechModels
import WhisperTranscription

/// Only the model the user chose is downloaded, and only after they opt in (ADR 0004, ADR 0005). Wi-Fi by
/// default; cellular only if they explicitly allow it. A background URLSession keeps going while the
/// app is suspended. Every file is verified against the manifest bundled in the signed app.
@MainActor
@Observable
final class ModelDownload {
    enum Status: Equatable {
        case notDownloaded
        case downloading(ModelInstaller.Progress)
        case failed(String)
        case ready
    }

    private static let allowsCellularKey = "modelDownloadAllowsCellular"
    private static let startedKey = "modelDownloadStarted"
    private static let log = Logger(subsystem: "com.captainduckay.dictator.ios", category: "model")

    /// Kept for the app delegate's background-session callback.
    static var transports: [String: BackgroundTransport] = [:]

    private(set) var status: Status = .notDownloaded
    /// The model this download is for; nil until the user picks one.
    private(set) var model: SpeechModel?
    /// Bumped when a model is installed or deleted, so views re-read `isInstalled(_:)`.
    private(set) var revision = 0
    /// True when the current network is cellular or otherwise "expensive" (hotspot, Low Data Mode).
    private(set) var isOnExpensiveNetwork = false
    @ObservationIgnored private var installer: ModelInstaller?
    @ObservationIgnored private let manifest: ModelManifest?
    @ObservationIgnored private let root: URL?
    @ObservationIgnored private var task: Task<Bool, Never>?
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored var onReady: (() async -> Void)?

    init() {
        manifest = try? ModelManifest.bundled()
        root = try? ModelInstaller.defaultRoot()
        if manifest == nil || root == nil { status = .failed("The app's model manifest is missing or invalid.") }
        monitor.pathUpdateHandler = { [weak self] path in
            let expensive = path.isExpensive || path.isConstrained
            Task { @MainActor in self?.isOnExpensiveNetwork = expensive }
        }
        monitor.start(queue: DispatchQueue(label: "model-download.network"))
    }

    private func installer(for model: SpeechModel) -> ModelInstaller? {
        guard let manifest, let root else { return nil }
        return ModelInstaller(manifest: manifest, modelID: model.rawValue, root: root)
    }

    /// True while a download runs; switching models waits until it finishes or is cancelled.
    var isBusy: Bool { if case .downloading = status { true } else { false } }

    /// Switches to `model`. Nothing is downloaded until the user taps Download (`start`).
    func select(_ model: SpeechModel) {
        guard model != self.model, task == nil else { return }
        self.model = model
        installer = installer(for: model)
        status = installer?.isInstalled == true ? .ready : (installer == nil ? status : .notDownloaded)
    }

    var isInstalled: Bool { installer?.isInstalled == true }
    func isInstalled(_ model: SpeechModel) -> Bool {
        _ = revision
        return installer(for: model)?.isInstalled == true
    }
    var installedModels: Set<SpeechModel> { Set(SpeechModel.allCases.filter(isInstalled)) }
    var folder: URL { installer?.folder ?? URL(filePath: "/nonexistent", directoryHint: .isDirectory) }
    var totalBytes: Int64 { installer?.totalBytes ?? 0 }
    var sizeText: String { ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file) }
    func bytes(of model: SpeechModel) -> Int64 { manifest?.totalBytes(for: model.rawValue) ?? 0 }
    func sizeText(of model: SpeechModel) -> String {
        ByteCountFormatter.string(fromByteCount: bytes(of: model), countStyle: .file)
    }

    /// Frees the storage of a model that isn't the selected one.
    func delete(_ model: SpeechModel) {
        guard model != self.model else { return }
        do {
            try installer(for: model)?.uninstall()
            Self.log.notice("model deleted: \(model.rawValue, privacy: .public)")
        } catch {
            Self.log.error("deleting model failed: \(String(describing: error), privacy: .public)")
        }
        revision += 1
    }

    /// After a relaunch, continue a download the user already started (never starts one by itself).
    func resumeIfStarted() {
        guard installer != nil, !isInstalled, defaults.bool(forKey: Self.startedKey) else { return }
        start(allowsCellular: defaults.bool(forKey: Self.allowsCellularKey))
    }

    /// The user tapped Download. `allowsCellular` only when they explicitly chose mobile data.
    func start(allowsCellular: Bool) {
        guard task == nil, let installer else { return }
        defaults.set(true, forKey: Self.startedKey)
        defaults.set(allowsCellular, forKey: Self.allowsCellularKey)
        let transport = Self.transport(allowsCellular: allowsCellular)
        let model = self.model
        status = .downloading(.init(completedBytes: 0, totalBytes: installer.totalBytes))
        task = Task {
            defer { task = nil }
            do {
                try await installer.install(using: transport) { progress in
                    Task { @MainActor in
                        if self.model == model, case .downloading = self.status { self.status = .downloading(progress) }
                    }
                }
                Self.log.notice("model download verified")
                defaults.set(false, forKey: Self.startedKey)
                revision += 1
                guard self.model == model else { return false }
                status = .ready
                await onReady?()
                return true
            } catch is CancellationError {
                status = .notDownloaded
                return false
            } catch {
                Self.log.error("model download failed: \(String(describing: error), privacy: .public)")
                status = .failed(Self.describe(error, allowsCellular: allowsCellular))
                return false
            }
        }
    }

    func cancel() {
        defaults.set(false, forKey: Self.startedKey)
        task?.cancel()
        Task { await Self.transport(allowsCellular: defaults.bool(forKey: Self.allowsCellularKey)).cancelAll() }
    }

    static func transport(allowsCellular: Bool) -> BackgroundTransport {
        let id = BackgroundTransport.identifier(allowsCellular: allowsCellular)
        if let existing = transports[id] { return existing }
        let made = BackgroundTransport(allowsCellular: allowsCellular)
        transports[id] = made
        return made
    }

    private static func describe(_ error: any Error, allowsCellular: Bool) -> String {
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .dataNotAllowed:
                return allowsCellular ? "No internet connection. Try again." : "No Wi-Fi connection. Try again on Wi-Fi."
            default: break
            }
        }
        if let error = error as? CocoaError, error.code == .fileWriteOutOfSpace {
            return "Not enough free storage."
        }
        return String(describing: error)
    }
}
