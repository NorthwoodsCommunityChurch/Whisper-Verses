import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @Environment(AppState.self) private var appState
    @State private var showingVersePicker = false
    @State private var isDropTargeted = false

    var body: some View {
        HSplitView {
            // Left panel: Whisper Transcript
            TranscriptPanelView()
                .frame(minWidth: 400)

            // Right side: Options (top, compact) + Capture Preview (bottom, fills)
            VStack(spacing: 0) {
                OptionsPanelView()

                Divider()

                CapturePreviewPanelView()
                    .frame(maxHeight: .infinity)
            }
            .frame(minWidth: 350)
        }
        .sheet(isPresented: $showingVersePicker) {
            ManualVersePicker()
                .environment(appState)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appState.importDocument()
                } label: {
                    Label("Import Document", systemImage: "doc.text.magnifyingglass")
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(!appState.isProPresenterConnected || appState.presentationIndexer?.map.isEmpty != false)
                .help("Import a manuscript or slide notes to pre-capture verse slides")

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

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
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
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    let ext = url.pathExtension.lowercased()
                    guard ext == "docx" || ext == "txt" else { return }
                    Task { @MainActor in
                        appState.lastImportedDocumentName = url.lastPathComponent
                        await appState.processDocumentFile(url)
                    }
                }
            }
            return true
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .background(Color.accentColor.opacity(0.08))
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.largeTitle)
                            Text("Drop to Import")
                                .font(.headline)
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .allowsHitTesting(false)
            }
        }
    }
}
