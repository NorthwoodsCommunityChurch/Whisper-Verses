import SwiftUI
import Sparkle

@main
struct WhisperVersesApp: App {
    @State private var appState = AppState()
    @State private var showOnboarding = false
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(appState)
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(.dark)
                .onAppear { showOnboarding = !appState.hasCompletedOnboarding }
                .sheet(isPresented: $showOnboarding) {
                    OnboardingView()
                        .environment(appState)
                }
                .onChange(of: appState.hasCompletedOnboarding) { _, completed in
                    if completed { showOnboarding = false }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    appState.saveSettings()
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }

        Settings {
            SettingsView()
                .environment(appState)
                .preferredColorScheme(.dark)
        }
    }
}
