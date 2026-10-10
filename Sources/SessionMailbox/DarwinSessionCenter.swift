import Foundation

#if os(iOS) || os(macOS) || os(visionOS)
/// Cross-process wake-up for the mailbox. The files are the data; this only says "look now".
public final class DarwinSessionCenter: @unchecked Sendable {
    public static let shared = DarwinSessionCenter()

    private let lock = NSLock()
    private var handlers: [String: @Sendable () -> Void] = [:]

    public func post(_ signal: SessionSignal) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(signal.rawValue as CFString),
            nil,
            nil,
            true
        )
    }

    /// Replaces any previous handler for this signal. The handler may run off the main thread.
    public func observe(_ signal: SessionSignal, handler: @escaping @Sendable () -> Void) {
        lock.lock()
        handlers[signal.rawValue] = handler
        lock.unlock()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            darwinNotificationCallback,
            signal.rawValue as CFString,
            nil,
            .deliverImmediately
        )
    }

    fileprivate func dispatch(_ name: String) {
        lock.lock()
        let handler = handlers[name]
        lock.unlock()
        handler?()
    }
}

private func darwinNotificationCallback(
    _ center: CFNotificationCenter?,
    _ observer: UnsafeMutableRawPointer?,
    _ name: CFNotificationName?,
    _ object: UnsafeRawPointer?,
    _ userInfo: CFDictionary?
) {
    guard let name else { return }
    DarwinSessionCenter.shared.dispatch(name.rawValue as String)
}
#endif
