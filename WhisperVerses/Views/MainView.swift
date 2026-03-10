import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var appState
    @State private var showingVersePicker = false

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
        .sheet(isPresented: $showingVersePicker) {
            ManualVersePicker()
                .environment(appState)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Pick Verse") {
                    showingVersePicker = true
                }

                Button(appState.isListening ? "Stop" : "Start Listening") {
                    Task { await appState.toggleListening() }
                }
                .keyboardShortcut("l", modifiers: .command)
                .foregroundStyle(appState.isListening ? .red : .accentColor)

                Button("Clear Folders") {
                    appState.clearOutputFolders()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button("Reset Whisper") {
                    Task { await appState.resetWhisper() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
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
