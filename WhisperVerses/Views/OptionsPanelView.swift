import CoreAudio
import SwiftUI

struct OptionsPanelView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: Theme.Space.med) {
            modelStatus
            errorBanner

            audioInputSection
            gainSection
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Surface.window)
    }

    // MARK: - Model status

    @ViewBuilder
    private var modelStatus: some View {
        if appState.isModelLoading {
            VStack(alignment: .leading, spacing: 4) {
                if appState.modelDownloadProgress > 0 && appState.modelDownloadProgress < 1 {
                    ProgressView(value: appState.modelDownloadProgress) {
                        Text("DOWNLOADING MODEL · \(Int(appState.modelDownloadProgress * 100))%")
                            .font(Theme.Typography.statusPill(9))
                            .tracking(1.5)
                            .foregroundStyle(Theme.Foreground.secondary)
                    }
                } else {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.5)
                        Text("LOADING WHISPER MODEL")
                            .font(Theme.Typography.statusPill(9))
                            .tracking(1.5)
                            .foregroundStyle(Theme.Foreground.secondary)
                    }
                }
            }
        } else if !appState.isModelLoaded && appState.transcriptionService != nil {
            Text("MODEL FAILED TO LOAD")
                .font(Theme.Typography.statusPill(9))
                .tracking(1.5)
                .foregroundStyle(Theme.Status.offline)
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let error = appState.errorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Brand.gold)
                Text(error)
                    .font(Theme.Typography.body(11))
                    .lineLimit(3)
                Spacer()
                Button {
                    appState.dismissError()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Foreground.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss error")
            }
            .padding(Theme.Space.small)
            .background(Theme.Status.offline.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
        }
    }

    // MARK: - Audio input

    private var audioInputSection: some View {
        @Bindable var state = appState
        return VStack(alignment: .leading, spacing: 6) {
            Text("AUDIO INPUT")
                .font(Theme.Typography.statusPill(9))
                .tracking(1.8)
                .foregroundStyle(Theme.Foreground.tertiary)
            HStack(spacing: Theme.Space.small) {
                Picker("", selection: $state.selectedAudioDeviceID) {
                    Text("Select device…").tag(nil as AudioDeviceID?)
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
    }

    // MARK: - Gain

    private var gainSection: some View {
        @Bindable var state = appState
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("INPUT GAIN")
                    .font(Theme.Typography.statusPill(9))
                    .tracking(1.8)
                    .foregroundStyle(Theme.Foreground.tertiary)
                Spacer()
                Text(String(format: "%.1f×", appState.inputGain))
                    .font(Theme.Typography.caption(11))
                    .foregroundStyle(Theme.Foreground.secondary)
                if appState.inputGain != 1.0 {
                    Button("RESET") {
                        appState.inputGain = 1.0
                        ThreadSafeAudioProcessor.inputGain = 1.0
                        appState.saveSettings()
                    }
                    .font(Theme.Typography.statusPill(9))
                    .tracking(1.2)
                    .foregroundStyle(Theme.Brand.lightBlue)
                    .buttonStyle(.plain)
                }
            }
            Slider(value: $state.inputGain, in: 0.5...3.0, step: 0.1)
                .tint(Theme.Brand.lightBlue)
                .onChange(of: appState.inputGain) { _, newValue in
                    ThreadSafeAudioProcessor.inputGain = newValue
                    appState.saveSettings()
                }
        }
    }
}
