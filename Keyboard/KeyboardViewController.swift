import DictatorIOS
import SwiftUI
import UIKit

@objc(KeyboardViewController)
final class KeyboardViewController: UIInputViewController {
    private let screen = KeyboardScreen()
    private var hosting: UIHostingController<KeyboardMicView>?
    private var poll: Task<Void, Never>?
    private var heightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        let constraint = view.heightAnchor.constraint(equalToConstant: KeyboardMetrics.height)
        constraint.priority = UILayoutPriority(999)
        constraint.isActive = true
        heightConstraint = constraint

        if let container = AppGroup.containerURL(), let mailbox = try? SessionMailbox(directory: container) {
            screen.session = KeyboardSession(
                mailbox: mailbox,
                inserter: KeyboardTextInserter(),
                contextBeforeCursor: { [weak self] in self?.textDocumentProxy.documentContextBeforeInput }
            )
        }
        DarwinSessionCenter.shared.observe(.host) { [weak self] in
            Task { @MainActor in await self?.screen.session?.refresh() }
        }
        DarwinSessionCenter.shared.observe(.delivery) { [weak self] in
            Task { @MainActor in await self?.screen.session?.refresh() }
        }

        let hosting = UIHostingController(rootView: KeyboardMicView(
            screen: screen,
            onSwitch: { [weak self] in self?.advanceToNextInputMode() }
        ))
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(hosting)
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hosting.didMove(toParent: self)
        self.hosting = hosting
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        screen.fullAccess = hasFullAccess
        screen.session?.inserter.proxy = UIKitTextDocumentProxy(textDocumentProxy)
        startPolling()
    }

    override func viewWillDisappear(_ animated: Bool) {
        poll?.cancel()
        poll = nil
        // Setting the proxy also forgets the last dictation: it's not offered for undo once the
        // keyboard goes away (the user may switch fields or keyboards and type).
        screen.session?.inserter.proxy = nil
        screen.session?.cancel()
        super.viewWillDisappear(animated)
    }

    private func startPolling() {
        poll?.cancel()
        poll = Task { [weak self] in
            while !Task.isCancelled {
                await self?.screen.session?.refresh()
                try? await Task.sleep(for: KeyboardMetrics.pollInterval)
            }
        }
    }
}

@MainActor
@Observable
final class KeyboardScreen {
    var session: KeyboardSession?
    var fullAccess = false
}

enum KeyboardMetrics {
    static let height: CGFloat = 216
    static let pollInterval: Duration = .milliseconds(300)
    static let buttonSize: CGFloat = 84
}
