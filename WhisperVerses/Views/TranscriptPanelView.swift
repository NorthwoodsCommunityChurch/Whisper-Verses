import SwiftUI

struct TranscriptPanelView: View {
    @Environment(AppState.self) private var appState
    @State private var copiedFlash = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Whisper Transcript")
                    .font(.headline)
                Spacer()
                Button {
                    let fullText = appState.confirmedSegments
                        .map { "\($0.formattedTime)  \($0.text)" }
                        .joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(fullText, forType: .string)
                    copiedFlash = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        copiedFlash = false
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: copiedFlash ? "checkmark" : "doc.on.doc")
                        Text(copiedFlash ? "Copied" : "Copy")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(appState.confirmedSegments.isEmpty)
                if appState.isListening {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                            .shadow(color: .red.opacity(0.6), radius: 4)
                        Text("Listening")
                            .font(.caption)
                            .bold()
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.03))

            // Transcript content - use LazyVStack for performance with many segments
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(appState.confirmedSegments) { segment in
                            TranscriptRow(segment: segment)
                                .id(segment.id)
                        }

                        // Current hypothesis (partial result)
                        if !appState.currentHypothesis.isEmpty {
                            HStack(alignment: .top, spacing: 8) {
                                Text("...")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 40, alignment: .trailing)

                                Text(appState.currentHypothesis)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .italic()
                                    .textSelection(.enabled)
                            }
                            .padding(.horizontal)
                            .id("hypothesis")
                        }

                        // Invisible anchor for auto-scroll with buffer space
                        Color.clear
                            .frame(height: 100)
                            .id("bottomAnchor")
                    }
                    .padding(.top, 8)
                }
                .scrollIndicators(.never)
                .onChange(of: appState.confirmedSegments.count) {
                    proxy.scrollTo("bottomAnchor", anchor: .bottom)
                }
            }

            // Empty state
            if appState.confirmedSegments.isEmpty && appState.currentHypothesis.isEmpty {
                ContentUnavailableView(
                    appState.isListening ? "Waiting for Speech" : "Not Listening",
                    systemImage: "waveform",
                    description: Text(appState.isListening ? "Listening for speech..." : "Press Start Listening to begin")
                )
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.white.opacity(0.03))
        .overlay(alignment: .leading) {
            // Red listening edge indicator
            if appState.isListening {
                Rectangle()
                    .fill(Color.red.opacity(0.6))
                    .frame(width: 3)
                    .shadow(color: .red.opacity(0.4), radius: 6, x: 3)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.isListening)
    }
}
