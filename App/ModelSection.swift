import DictationCore
import SpeechModels
import SwiftUI

/// The explicit opt-in for the model download (ADR 0004): shows the size, recommends Wi-Fi, and only
/// uses mobile data when the user turns it on and confirms. Nothing downloads before they tap.
struct ModelSection: View {
    let download: ModelDownload
    let state: DictationState
    let chosen: SpeechModel?
    @State private var allowsCellular = false
    @State private var confirmCellular = false

    private var name: String { chosen?.displayName ?? "speech" }

    var body: some View {
        if chosen == nil {
            Text("Choose a speech model below. Nothing is downloaded until you choose one and tap Download.")
        } else {
            status
        }
    }

    @ViewBuilder private var status: some View {
        switch download.status {
        case .ready:
            if case .unavailable(let message) = state {
                Text(message).foregroundStyle(.red)
            } else {
                Text("\(name) is downloaded and runs on this iPhone. Dictation works offline.")
            }
        case .downloading(let progress):
            ProgressView(value: progress.fraction) {
                Text("Downloading \(name)…")
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
            Text("Dictator needs the \(name) speech model (\(download.sizeText)). It is downloaded once from Hugging Face, checked against a hash built into the app, and then works offline. Wi-Fi is recommended.")
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
            Text("Audio never leaves the device; downloading the model you choose is the only network use.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func format(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

/// One model's name, size, languages, accuracy and speed. Used by the picker and the model list.
struct ModelSummary: View {
    let model: SpeechModel
    let size: String
    var recommended = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(model.displayName).font(.headline)
                if recommended {
                    Text("Recommended")
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                }
            }
            Text("\(size) download · \(model.languageNote) · \(model.source)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(model.accuracyNote).font(.subheadline)
            Text(model.speedNote).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

/// The models, best first: switch to another (downloads only after the usual opt-in) or delete
/// one that isn't in use.
struct ModelList: View {
    let download: ModelDownload
    let chosen: SpeechModel?
    let choose: (SpeechModel) -> Void

    var body: some View {
        ForEach(SpeechModel.ranked) { model in
            VStack(alignment: .leading, spacing: 8) {
                ModelSummary(model: model, size: download.sizeText(of: model), recommended: model == SpeechModel.ranked.first)
                HStack {
                    if model == chosen {
                        Text("In use").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Button(download.isInstalled(model) ? "Use" : "Choose") { choose(model) }
                            .buttonStyle(.bordered)
                            .disabled(download.isBusy)
                        if download.isInstalled(model) {
                            Button("Delete", role: .destructive) { download.delete(model) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        if download.isBusy {
            Text("Cancel the running download to switch models.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// Shown at launch only while no model is chosen. Picking one downloads nothing by itself: the
/// Model section then asks for the download, with the usual Wi-Fi / mobile data choice.
struct ModelPickerSheet: View {
    let download: ModelDownload
    let choose: (SpeechModel) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Dictator transcribes on this iPhone. Choose one model; only that one is downloaded, after you confirm. You can switch later.")
                        .font(.subheadline)
                }
                Section("Best first") {
                    ForEach(SpeechModel.ranked) { model in
                        Button { choose(model) } label: {
                            ModelSummary(model: model, size: download.sizeText(of: model), recommended: model == SpeechModel.ranked.first)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Choose a Speech Model")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
    }
}
