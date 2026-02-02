import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @State private var currentStep = 0

    private let steps: [OnboardingStep] = [
        OnboardingStep(
            icon: "waveform",
            title: "Welcome to Whisper Verses",
            description: "Whisper Verses listens to your pastor's sermon in real-time, detects Bible verse references, and automatically captures the corresponding slide from ProPresenter 7.",
            details: [
                "Real-time speech-to-text via WhisperKit",
                "Automatic Bible reference detection",
                "ProPresenter 7 slide capture to PNG",
                "Transparent PNGs dropped into a watched folder"
            ]
        ),
        OnboardingStep(
            icon: "speaker.wave.3",
            title: "Audio Setup",
            description: "Whisper Verses needs an audio input to listen to. For best results, use a virtual audio device like AudioLoop to route system audio.",
            details: [
                "Install AudioLoop (or similar virtual audio driver)",
                "Route ProPresenter or system audio through it",
                "Select the virtual device in the Audio Input dropdown",
                "You can also use a physical microphone"
            ]
        ),
        OnboardingStep(
            icon: "network",
            title: "ProPresenter Connection",
            description: "Enable the Pro7 network API so Whisper Verses can retrieve slide images.",
            details: [
                "In Pro7: Settings → Network → Enable Network",
                "Note the port number (default: 1025)",
                "Enter the host and port in the Options panel",
                "Click Connect to establish the link"
            ]
        ),
        OnboardingStep(
            icon: "books.vertical",
            title: "Bible Library",
            description: "Create Bible presentations in ProPresenter with transparent backgrounds. Each book should be a separate presentation.",
            details: [
                "Install a Bible translation in Pro7 (e.g., KJV, NIV84)",
                "Create a Bible template with transparent background",
                "Generate all 66 books as presentations",
                "Place them in a dedicated library (e.g., \"Bible KJV\")"
            ]
        ),
        OnboardingStep(
            icon: "checkmark.circle",
            title: "Ready to Go",
            description: "You're all set. Connect to ProPresenter, index your Bible library, then hit Start Listening during a sermon.",
            details: [
                "Connect to Pro7 and click Index to map Bible books",
                "Choose an output folder (Pro7 folder playlist)",
                "Press Start Listening (⌘L) when the sermon begins",
                "Detected verses appear as PNGs in your output folder"
            ]
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Step content
            let step = steps[currentStep]

            VStack(spacing: 16) {
                Image(systemName: step.icon)
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)
                    .frame(height: 60)

                Text(step.title)
                    .font(.title2)
                    .bold()

                Text(step.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(step.details, id: \.self) { detail in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(.secondary)
                                .padding(.top, 6)
                            Text(detail)
                                .font(.callout)
                        }
                    }
                }
                .frame(maxWidth: 380, alignment: .leading)
                .padding(.top, 8)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation
            HStack {
                // Step indicators
                HStack(spacing: 6) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }

                Spacer()

                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                    .buttonStyle(.bordered)
                }

                if currentStep < steps.count - 1 {
                    Button("Next") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        appState.completeOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 520, height: 480)
    }
}

private struct OnboardingStep {
    let icon: String
    let title: String
    let description: String
    let details: [String]
}
