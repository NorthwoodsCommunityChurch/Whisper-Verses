import CoreAudio
import SwiftUI

struct OptionsPanelView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: 12) {
            // Model status (shown at top so it's always visible)
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
                    .accessibilityLabel("Dismiss error")
                }
                .padding(8)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }

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

                    AnimatedWaveformView(
                        level: appState.isListening ? appState.audioLevel : appState.audioDeviceManager.currentLevel,
                        isActive: appState.isListening || appState.audioDeviceManager.currentLevel > 0.01
                    )
                    .frame(width: 80, height: 16)
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
            }

            // Pro7 status line (read-only indicator)
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.isProPresenterConnected ? Color.green : Color.red.opacity(0.5))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)

                if appState.isProPresenterConnected {
                    if let indexer = appState.presentationIndexer, indexer.indexedBookCount > 0 {
                        Text("Pro7 connected \u{00B7} \(indexer.indexedBookCount)/66 books")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Pro7 connected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Pro7 disconnected")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
    }
}
