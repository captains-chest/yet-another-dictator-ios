import DictationCore
import SwiftUI

/// The explicit opt-in for the model download (ADR 0004): shows the size, recommends Wi-Fi, and only
/// uses mobile data when the user turns it on and confirms. Nothing downloads before they tap.
struct ModelSection: View {
    let download: ModelDownload
    let state: DictationState
    @State private var allowsCellular = false
    @State private var confirmCellular = false

    var body: some View {
        switch download.status {
        case .ready:
            if case .unavailable(let message) = state {
                Text(message).foregroundStyle(.red)
            } else {
                Text("Whisper Small is downloaded and runs on this iPhone. Dictation works offline.")
            }
        case .downloading(let progress):
            ProgressView(value: progress.fraction) {
                Text("Downloading Whisper Small…")
            } currentValueLabel: {
                Text("\(format(progress.completedBytes)) of \(format(progress.totalBytes))")
            }
            if download.isOnExpensiveNetwork && !allowsCellular {
                Text("Waiting for Wi-Fi. The download continues in the background when you're on Wi-Fi.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button("Cancel Download", role: .destructive) { download.cancel() }
        case .notDownloaded, .failed:
            if case .failed(let message) = download.status {
                Text(message).foregroundStyle(.red)
            }
            Text("Dictator needs the Whisper Small speech model (\(download.sizeText)). It is downloaded once from Hugging Face, checked against a hash built into the app, and then works offline. Wi-Fi is recommended.")
            Toggle("Use Mobile Data", isOn: $allowsCellular)
            Button("Download Model (\(download.sizeText))") {
                if allowsCellular && download.isOnExpensiveNetwork {
                    confirmCellular = true
                } else {
                    download.start(allowsCellular: allowsCellular)
                }
            }
            .confirmationDialog(
                "Download \(download.sizeText) over mobile data?",
                isPresented: $confirmCellular,
                titleVisibility: .visible
            ) {
                Button("Download over Mobile Data") { download.start(allowsCellular: true) }
                Button("Wait for Wi-Fi") { download.start(allowsCellular: false) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You're not on Wi-Fi. This may use your data plan.")
            }
            Text("Audio never leaves the device; the one-time model download is the only network use.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func format(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}
