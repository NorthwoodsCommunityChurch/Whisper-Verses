import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @Environment(AppState.self) private var appState
    @State private var showingVersePicker = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            ChromeBar(
                onPickVerse: { showingVersePicker = true },
                onImport:    { appState.importDocument() }
            )

            HSplitView {
                TranscriptPanelView()
                    .frame(minWidth: 480)

                VStack(spacing: 0) {
                    OptionsPanelView()
                    Divider()
                        .background(Theme.Surface.divider)
                    CapturePreviewPanelView()
                        .frame(maxHeight: .infinity)
                }
                .frame(minWidth: 360)
                .background(Theme.Surface.window)
            }
        }
        .ignoresSafeArea(.all, edges: .top)
        .background(Theme.Surface.window)
        .sheet(isPresented: $showingVersePicker) {
            ManualVersePicker()
                .environment(appState)
        }
        .toolbar(.hidden, for: .windowToolbar)
        .task {
            appState.audioDeviceManager.refreshDevices()
            appState.availableAudioDevices = appState.audioDeviceManager.devices

            if let deviceID = appState.selectedAudioDeviceID,
               let device = appState.availableAudioDevices.first(where: { $0.id == deviceID }) {
                appState.audioDeviceManager.selectDevice(device)
            }

            if appState.proPresenterHost != "127.0.0.1" || appState.proPresenterPort != 1025 {
                await appState.connectToProPresenter(silent: true)
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
                    .strokeBorder(Theme.Brand.lightBlue, style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .background(Theme.Brand.lightBlue.opacity(0.08))
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.largeTitle)
                            Text("DROP TO IMPORT")
                                .font(Theme.Typography.statusPill(13))
                                .tracking(2.0)
                        }
                        .foregroundStyle(Theme.Brand.lightBlue)
                    }
                    .allowsHitTesting(false)
            }
        }
        .background(GlobalShortcutsView { showingVersePicker = true })
        .background(WindowChromeConfigurator())
    }
}

/// Pushes window content under the title bar so the ChromeBar sits flush at
/// the top edge. Traffic-light buttons remain (window stays movable) and
/// overlay the chrome bar's leading 78pt — which is why ChromeBar reserves
/// that padding.
private struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = WindowAwareView()
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        if let aware = nsView as? WindowAwareView {
            aware.applyChrome()
        }
    }
}

private final class WindowAwareView: NSView {
    private var notificationToken: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyChrome()
        // SwiftUI keeps re-hiding NSTitlebarContainerView after our config.
        // Re-enforce on every layout update.
        if let window {
            notificationToken = NotificationCenter.default.addObserver(
                forName: NSWindow.didUpdateNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.applyChrome()
            }
        }
    }

    deinit {
        if let token = notificationToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func applyChrome() {
        guard let window else { return }
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true

        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = false
        }

        // SwiftUI's .titlebarAppearsTransparent + fullSizeContentView combo
        // hides `NSTitlebarContainerView` (alpha=0, isHidden=true), which is
        // the grandparent of the traffic-light buttons — so the buttons exist
        // and are visible themselves but their container is invisible. Walk
        // up from the close button and force the container back on.
        var v: NSView? = window.standardWindowButton(.closeButton)
        while let view = v {
            view.isHidden = false
            view.alphaValue = 1.0
            v = view.superview
            if String(describing: type(of: view)).contains("TitlebarContainer") { break }
        }
    }
}

/// Invisible buttons hosting the keyboard shortcuts that previously lived
/// on toolbar items. Keeps ⌘L (Listen), ⌘⇧I (Import), ⌘⇧K (Clear), ⌘⇧R
/// (Reset Whisper) functional even though there's no longer a toolbar.
private struct GlobalShortcutsView: View {
    @Environment(AppState.self) private var appState
    let onPickVerse: () -> Void

    var body: some View {
        ZStack {
            Button("Listen") { Task { await appState.toggleListening() } }
                .keyboardShortcut("l", modifiers: .command)
            Button("Import") { appState.importDocument() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(!appState.isProPresenterConnected || appState.presentationIndexer?.map.isEmpty != false)
            Button("Clear Folders") { appState.clearOutputFolders() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Button("Reset Whisper") { Task { await appState.resetWhisper() } }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Pick Verse") { onPickVerse() }
                .keyboardShortcut("p", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .frame(width: 0, height: 0)
    }
}
