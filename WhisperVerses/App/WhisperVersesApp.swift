import SwiftUI

@main
struct WhisperVersesApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(appState)
                .frame(minWidth: 900, minHeight: 600)
                .sheet(isPresented: .init(
                    get: { !appState.hasCompletedOnboarding },
                    set: { if !$0 { appState.completeOnboarding() } }
                )) {
                    OnboardingView()
                        .environment(appState)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    appState.saveSettings()
                }
        }
        .windowResizability(.contentMinSize)
    }
}
