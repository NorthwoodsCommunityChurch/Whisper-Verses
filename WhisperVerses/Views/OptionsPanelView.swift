import CoreAudio
import SwiftUI

struct OptionsPanelView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: 12) {
            Text("Options")
                .font(.headline)

            // Audio Device
            VStack(alignment: .leading, spacing: 4) {
                Text("Audio Input")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Picker("", selection: $state.selectedAudioDeviceID) {
                        Text("Select device...").tag(nil as AudioDeviceID?)
                        ForEach(appState.availableAudioDevices) { device in
                            Text(device.name).tag(device.id as AudioDeviceID?)
                        }
                    }
                    .labelsHidden()

                    AudioLevelView(level: appState.audioDeviceManager.currentLevel)
                        .frame(width: 60, height: 16)
                }
            }
            .onChange(of: appState.selectedAudioDeviceID) { _, newValue in
                if let deviceID = newValue,
                   let device = appState.availableAudioDevices.first(where: { $0.id == deviceID }) {
                    appState.audioDeviceManager.selectDevice(device)
                }
            }

            // Pro7 Connection
            VStack(alignment: .leading, spacing: 4) {
                Text("ProPresenter")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    ConnectionStatusView(isConnected: appState.isProPresenterConnected)
                    TextField("Host", text: $state.proPresenterHost)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(maxWidth: 120)
                    Text(":")
                        .foregroundStyle(.secondary)
                    TextField("Port", value: $state.proPresenterPort, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(maxWidth: 60)
                    Button("Connect") {
                        Task { await appState.connectToProPresenter() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // ProPresenter Library
            VStack(alignment: .leading, spacing: 4) {
                Text("ProPresenter Library")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("Library name in Pro7", text: $state.bibleLibraryName)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    Button("Index") {
                        Task { await appState.indexBibleLibrary() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                if let indexer = appState.presentationIndexer {
                    if indexer.isIndexing {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.5)
                            Text("Indexing library...")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else if let error = indexer.errorMessage {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    } else if indexer.indexedBookCount > 0 {
                        Text("Indexed \(indexer.indexedBookCount)/66 books")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            }

            // Output Folder
            VStack(alignment: .leading, spacing: 4) {
                Text("Output Folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(appState.outputFolderURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        selectOutputFolder()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                }
            }

            // Confidence Threshold
            VStack(alignment: .leading, spacing: 4) {
                Text("Confidence Threshold: \(Int(appState.confidenceThreshold * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $state.confidenceThreshold, in: 0.3...1.0, step: 0.05)
            }

            Spacer()

            // Action Buttons
            HStack {
                Button(appState.isListening ? "Stop" : "Start Listening") {
                    Task { await appState.toggleListening() }
                }
                .buttonStyle(.borderedProminent)
                .tint(appState.isListening ? .red : .accentColor)
                .keyboardShortcut("l", modifiers: .command)

                Button("Clear Folder") {
                    appState.clearOutputFolder()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }

            // Model status
            if appState.isModelLoading {
                VStack(alignment: .leading, spacing: 4) {
                    if appState.modelDownloadProgress > 0 && appState.modelDownloadProgress < 1 {
                        ProgressView(value: appState.modelDownloadProgress) {
                            Text("Downloading model (\(Int(appState.modelDownloadProgress * 100))%)...")
                                .font(.caption)
                        }
                    } else {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.5)
                            Text("Loading Whisper model...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else if !appState.isModelLoaded && appState.transcriptionService != nil {
                Text("Model failed to load")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Update banner
            UpdateBannerView()

            // Error banner
            if let error = appState.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.caption)
                        .lineLimit(3)
                    Spacer()
                    Button {
                        appState.dismissError()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding()
        .background(.background)
    }

    private func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Select Output Folder"
        if panel.runModal() == .OK, let url = panel.url {
            appState.outputFolderURL = url
            appState.saveSettings()
        }
    }
}
