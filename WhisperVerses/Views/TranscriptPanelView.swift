import SwiftUI

struct TranscriptPanelView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Whisper Transcript")
                    .font(.headline)
                Spacer()
                if appState.isListening {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        Text("Listening")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Transcript content
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
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
                            }
                            .padding(.horizontal)
                            .id("hypothesis")
                        }
                    }
                    .textSelection(.enabled)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.never)
                .onChange(of: appState.confirmedSegments.count) {
                    if let last = appState.confirmedSegments.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            // Empty state
            if appState.confirmedSegments.isEmpty && appState.currentHypothesis.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text(appState.isListening ? "Waiting for speech..." : "Press Start Listening to begin")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .background(.background)
    }
}

struct TranscriptRow: View {
    let segment: TranscriptSegment

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(segment.formattedTime)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)

            if segment.detectedReferences.isEmpty {
                Text(segment.text)
                    .font(.body)
            } else {
                // Highlight text containing verse references
                Text(segment.text)
                    .font(.body)
                    .padding(2)
                    .background(Color.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
            }
        }
        .padding(.horizontal)
    }
}
