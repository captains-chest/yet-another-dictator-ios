import UIKit
import WhisperTranscription

/// Hands background URLSession events (the model download finishing while the app was suspended
/// or terminated) to the matching transport.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier.hasPrefix(BackgroundTransport.identifierPrefix) else {
            completionHandler()
            return
        }
        let transport = ModelDownload.transport(allowsCellular: identifier.hasSuffix(".any"))
        nonisolated(unsafe) let handler = completionHandler
        transport.setBackgroundEventsHandler { handler() }
    }
}
