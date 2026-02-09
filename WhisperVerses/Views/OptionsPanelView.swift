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

                    AudioLevelView(level: appState.isListening ? appState.audioLevel : appState.audioDeviceManager.currentLevel)
                        .frame(width: 60, height: 16)
                }
            }
            .onChange(of: appState.selectedAudioDeviceID) { _, newValue in
                if let deviceID = newValue,
                   let device = appState.availableAudioDevices.first(where: { $0.id == deviceID }) {
                    appState.audioDeviceManager.selectDevice(device)
                }
            }

            // Input Gain
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Input Gain: \(String(format: "%.1fx", appState.inputGain))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if appState.inputGain != 1.0 {
                        Button("Reset") {
                            appState.inputGain = 1.0
                            ThreadSafeAudioProcessor.inputGain = 1.0
                            appState.saveSettings()
                        }
                        .font(.caption2)
                        .buttonStyle(.borderless)
                    }
                }
                Slider(value: $state.inputGain, in: 0.5...3.0, step: 0.1)
                    .onChange(of: appState.inputGain) { _, newValue in
                        ThreadSafeAudioProcessor.inputGain = newValue
                        appState.saveSettings()
                    }
                Text("Boost quiet audio or reduce loud audio before processing")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
                        HStack(spacing: 8) {
                            Text("Indexed \(indexer.indexedBookCount)/66 books")
                                .font(.caption2)
                                .foregroundStyle(.green)

                            if !indexer.missingBooks.isEmpty {
                                Menu {
                                    ForEach(indexer.missingBooks) { book in
                                        Text(book.name)
                                    }
                                } label: {
                                    Label("\(indexer.missingBooks.count) missing", systemImage: "exclamationmark.triangle")
                                        .font(.caption2)
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                            }
                        }
                    }
                }
            }

            // Output Folders
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Output Folders")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        addOutputFolder()
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Add output folder")
                }

                ForEach(appState.outputFolderURLs, id: \.self) { folderURL in
                    HStack(spacing: 6) {
                        // Availability indicator
                        Circle()
                            .fill(appState.outputFolderAvailability[folderURL] == true ? Color.green : Color.red)
                            .frame(width: 8, height: 8)

                        Text(folderURL.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        // Remove button (only if more than one folder)
                        if appState.outputFolderURLs.count > 1 {
                            Button {
                                appState.removeOutputFolder(folderURL)
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove folder")
                        }
                    }
                }

                // Warning if any folder unavailable
                let unavailableCount = appState.outputFolderURLs.filter { appState.outputFolderAvailability[$0] != true }.count
                if unavailableCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("\(unavailableCount) folder\(unavailableCount > 1 ? "s" : "") not available")
                            .font(.caption)
                        Spacer()
                        Button("Retry") {
                            appState.checkOutputFolderAvailability()
                        }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(6)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            // Confidence Threshold
            VStack(alignment: .leading, spacing: 4) {
                Text("Confidence Threshold: \(Int(appState.confidenceThreshold * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $state.confidenceThreshold, in: 0.3...1.0, step: 0.05)
            }

            // Manuscript Web Server
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Manuscript Server")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { appState.webServer.isRunning },
                        set: { enabled in
                            if enabled {
                                appState.startWebServer()
                            } else {
                                appState.stopWebServer()
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                HStack(spacing: 8) {
                    Text("Port:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Port", value: $state.webServerPort, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(maxWidth: 60)
                        .disabled(appState.webServer.isRunning)
                        .onChange(of: appState.webServerPort) { _, _ in
                            appState.saveSettings()
                        }

                    if appState.webServer.isRunning {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("\(appState.webServer.connectionCount) client\(appState.webServer.connectionCount == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if appState.webServer.isRunning {
                        Button("Open") {
                            if let url = URL(string: "http://localhost:\(appState.webServerPort)") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if appState.webServer.isRunning {
                    Text("http://localhost:\(appState.webServerPort)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }

            // HyperDeck (for clip marking)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("HyperDeck")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { appState.hyperDeckClient.isConnected },
                        set: { enabled in
                            if enabled {
                                appState.connectHyperDeck()
                            } else {
                                appState.disconnectHyperDeck()
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(appState.hyperDeckHost.isEmpty)
                }

                HStack(spacing: 8) {
                    TextField("IP Address", text: $state.hyperDeckHost)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(maxWidth: 120)
                        .disabled(appState.hyperDeckClient.isConnected)
                        .onChange(of: appState.hyperDeckHost) { _, _ in
                            appState.saveSettings()
                        }

                    Text(":")
                        .foregroundStyle(.secondary)

                    TextField("Port", value: $state.hyperDeckPort, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(maxWidth: 50)
                        .disabled(appState.hyperDeckClient.isConnected)
                        .onChange(of: appState.hyperDeckPort) { _, _ in
                            appState.saveSettings()
                        }

                    if appState.hyperDeckClient.isConnected {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text(appState.hyperDeckClient.currentTimecode)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = appState.hyperDeckClient.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                Text("Connect to HyperDeck for timecode-marked clips")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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

                Button("Clear Folders") {
                    appState.clearOutputFolders()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button("Reset Whisper") {
                    appState.resetWhisper()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("r", modifiers: [.command, .shift])
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

    private func addOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Add Output Folder"
        if panel.runModal() == .OK, let url = panel.url {
            appState.addOutputFolder(url)
        }
    }
}
