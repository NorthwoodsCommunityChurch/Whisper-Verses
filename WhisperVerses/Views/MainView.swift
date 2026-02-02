import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HSplitView {
            // Left panel: Whisper Transcript
            TranscriptPanelView()
                .frame(minWidth: 400)

            // Right side: Options (top) + Capture Preview (bottom)
            VSplitView {
                OptionsPanelView()
                    .frame(minHeight: 200)

                CapturePreviewPanelView()
                    .frame(minHeight: 250)
            }
            .frame(minWidth: 350)
        }
        .task {
            appState.audioDeviceManager.refreshDevices()
            appState.availableAudioDevices = appState.audioDeviceManager.devices

            // Start level monitoring for previously saved device
            if let deviceID = appState.selectedAudioDeviceID,
               let device = appState.availableAudioDevices.first(where: { $0.id == deviceID }) {
                appState.audioDeviceManager.selectDevice(device)
            }

            // Auto-connect to Pro7 if host was previously saved
            if appState.proPresenterHost != "127.0.0.1" || appState.proPresenterPort != 1025 {
                await appState.connectToProPresenter()
            }
        }
    }
}
