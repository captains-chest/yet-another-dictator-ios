import Foundation
import Network
import Observation
import OSLog
import WhisperTranscription

/// The model is downloaded only after the user opts in on the Model screen (ADR 0004). Wi-Fi by
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

    static let modelID = "openai_whisper-small_216MB"
    private static let allowsCellularKey = "modelDownloadAllowsCellular"
    private static let startedKey = "modelDownloadStarted"
    private static let log = Logger(subsystem: "com.captainduckay.dictator.ios", category: "model")

    /// Kept for the app delegate's background-session callback.
    static var transports: [String: BackgroundTransport] = [:]

    private(set) var status: Status = .notDownloaded
    /// True when the current network is cellular or otherwise "expensive" (hotspot, Low Data Mode).
    private(set) var isOnExpensiveNetwork = false
    @ObservationIgnored private let installer: ModelInstaller?
    @ObservationIgnored private var task: Task<Bool, Never>?
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored var onReady: (() async -> Void)?

    init() {
        installer = try? ModelInstaller(
            manifest: ModelManifest.bundled(), modelID: Self.modelID, root: ModelInstaller.defaultRoot()
        )
        if installer == nil { status = .failed("The app's model manifest is missing or invalid.") }
        if installer?.isInstalled == true { status = .ready }
        monitor.pathUpdateHandler = { [weak self] path in
            let expensive = path.isExpensive || path.isConstrained
            Task { @MainActor in self?.isOnExpensiveNetwork = expensive }
        }
        monitor.start(queue: DispatchQueue(label: "model-download.network"))
    }

    var isInstalled: Bool { installer?.isInstalled == true }
    var folder: URL { installer?.folder ?? URL(filePath: "/nonexistent", directoryHint: .isDirectory) }
    var totalBytes: Int64 { installer?.totalBytes ?? 0 }
    var sizeText: String { ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file) }

    /// After a relaunch, continue a download the user already started (never starts one by itself).
    func resumeIfStarted() {
        guard !isInstalled, defaults.bool(forKey: Self.startedKey) else { return }
        start(allowsCellular: defaults.bool(forKey: Self.allowsCellularKey))
    }

    /// The user tapped Download. `allowsCellular` only when they explicitly chose mobile data.
    func start(allowsCellular: Bool) {
        guard task == nil, let installer else { return }
        defaults.set(true, forKey: Self.startedKey)
        defaults.set(allowsCellular, forKey: Self.allowsCellularKey)
        let transport = Self.transport(allowsCellular: allowsCellular)
        status = .downloading(.init(completedBytes: 0, totalBytes: installer.totalBytes))
        task = Task {
            defer { task = nil }
            do {
                try await installer.install(using: transport) { progress in
                    Task { @MainActor in
                        if case .downloading = self.status { self.status = .downloading(progress) }
                    }
                }
                Self.log.notice("model download verified")
                defaults.set(false, forKey: Self.startedKey)
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
