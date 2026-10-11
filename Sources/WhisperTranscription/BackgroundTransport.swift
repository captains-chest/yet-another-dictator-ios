import Foundation

/// iOS transport: a background `URLSession`, so the download continues while the app is suspended
/// and survives the app being terminated by the system. Wi-Fi only unless the user allowed cellular
/// (`allowsExpensiveNetworkAccess` / `allowsConstrainedNetworkAccess`, ADR 0004).
///
/// Each file is one download task whose `taskDescription` is the `.part` path, so a file that
/// finished while the app wasn't running is still moved into place on the next launch. A failed or
/// cancelled task leaves resume data next to the `.part` path, and the next attempt resumes from it.
public final class BackgroundTransport: NSObject, ModelTransport, URLSessionDownloadDelegate, @unchecked Sendable {
    public static let identifierPrefix = "com.captainduckay.dictator.ios.model"

    private let lock = NSLock()
    private var waiters: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var progressHandlers: [Int: @Sendable (Int64) -> Void] = [:]
    private var moveErrors: [Int: any Error] = [:]
    private var finishEvents: (@Sendable () -> Void)?
    private var session: URLSession!

    public let allowsCellular: Bool

    public init(allowsCellular: Bool) {
        self.allowsCellular = allowsCellular
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier(allowsCellular: allowsCellular))
        configuration.allowsExpensiveNetworkAccess = allowsCellular
        configuration.allowsConstrainedNetworkAccess = allowsCellular
        configuration.allowsCellularAccess = allowsCellular
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    public static func identifier(allowsCellular: Bool) -> String {
        identifierPrefix + (allowsCellular ? ".any" : ".wifi")
    }

    /// Call from `application(_:handleEventsForBackgroundURLSession:completionHandler:)`.
    public func setBackgroundEventsHandler(_ handler: @escaping @Sendable () -> Void) {
        lock.withLock { finishEvents = handler }
    }

    /// Stops every running task, keeping resume data, e.g. when the user cancels.
    public func cancelAll() async {
        for task in await session.allTasks {
            (task as? URLSessionDownloadTask)?.cancel(byProducingResumeData: { _ in })
        }
    }

    public func fetch(_ entry: ModelManifest.Entry, into part: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        if (try? ModelInstaller.size(of: part)) == entry.bytes { return }
        let resumeURL = part.appendingPathExtension("resume")
        let partPath = part.path(percentEncoded: false)

        let running = await session.allTasks.first { $0.taskDescription == partPath && $0.state == .running }
        let task: URLSessionTask
        if let running {
            task = running
        } else if let data = try? Data(contentsOf: resumeURL) {
            try? FileManager.default.removeItem(at: resumeURL)
            task = session.downloadTask(withResumeData: data)
        } else {
            try? FileManager.default.removeItem(at: part)
            task = session.downloadTask(with: URLRequest(url: entry.url, timeoutInterval: 60))
        }
        task.taskDescription = partPath
        let id = task.taskIdentifier
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                lock.withLock {
                    waiters[id] = continuation
                    progressHandlers[id] = progress
                }
                if running == nil { task.resume() }
            }
        } onCancel: {
            (task as? URLSessionDownloadTask)?.cancel(byProducingResumeData: { _ in })
        }
    }

    // MARK: URLSessionDownloadDelegate

    public func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData _: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite _: Int64
    ) {
        let handler = lock.withLock { progressHandlers[downloadTask.taskIdentifier] }
        handler?(totalBytesWritten)
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temporary file is deleted when this returns: move it now. Verification happens later.
        guard let path = downloadTask.taskDescription else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        do {
            guard (200..<300).contains(status) else { throw URLError(.badServerResponse) }
            let target = URL(filePath: path)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: location, to: target)
        } catch {
            lock.withLock { moveErrors[downloadTask.taskIdentifier] = error }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let id = task.taskIdentifier
        if let error = error as? URLError, let data = error.downloadTaskResumeData, let path = task.taskDescription {
            try? data.write(to: URL(filePath: path).appendingPathExtension("resume"))
        }
        let (waiter, moveError) = lock.withLock {
            progressHandlers[id] = nil
            return (waiters.removeValue(forKey: id), moveErrors.removeValue(forKey: id))
        }
        if let failure = error ?? moveError {
            waiter?.resume(throwing: failure)
        } else {
            waiter?.resume()
        }
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let handler = lock.withLock { () -> (@Sendable () -> Void)? in
            defer { finishEvents = nil }
            return finishEvents
        }
        if let handler { DispatchQueue.main.async { handler() } }
    }
}
