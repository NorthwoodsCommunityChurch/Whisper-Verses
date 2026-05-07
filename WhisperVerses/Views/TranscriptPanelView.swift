import SwiftUI

struct TranscriptPanelView: View {
    @Environment(AppState.self) private var appState
    @State private var copiedFlash = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.Surface.panel)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Space.small) {
            Rectangle()
                .fill(Theme.Brand.blue)
                .frame(width: 14, height: 2)
            Text("TRANSCRIPT")
                .font(Theme.Typography.sectionHeader(10))
                .tracking(1.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Foreground.secondary)

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
                HStack(spacing: 4) {
                    Image(systemName: copiedFlash ? "checkmark" : "doc.on.doc")
                    Text(copiedFlash ? "COPIED" : "COPY")
                        .tracking(1.2)
                }
                .font(Theme.Typography.statusPill(10))
                .foregroundStyle(copiedFlash ? Theme.Brand.green : Theme.Foreground.secondary)
            }
            .buttonStyle(.plain)
            .disabled(appState.confirmedSegments.isEmpty)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.med)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if appState.confirmedSegments.isEmpty && appState.currentHypothesis.isEmpty {
            IdleHero(onStart: { Task { await appState.toggleListening() } })
        } else {
            transcriptScroll
        }
    }

    private var transcriptScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Space.med) {
                    ForEach(appState.confirmedSegments) { segment in
                        TranscriptRow(segment: segment)
                            .id(segment.id)
                    }

                    if !appState.currentHypothesis.isEmpty {
                        HStack(alignment: .top, spacing: Theme.Space.med) {
                            Text("···")
                                .font(Theme.Typography.caption(11))
                                .foregroundStyle(Theme.Foreground.tertiary)
                                .frame(width: 70, alignment: .trailing)

                            Text(appState.currentHypothesis)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(Theme.Foreground.secondary)
                                .italic()
                                .textSelection(.enabled)
                        }
                        .padding(.horizontal, Theme.Space.lg)
                        .id("hypothesis")
                    }

                    Color.clear
                        .frame(height: 100)
                        .id("bottomAnchor")
                }
                .padding(.vertical, Theme.Space.small)
            }
            .scrollIndicators(.never)
            .onChange(of: appState.confirmedSegments.count) {
                proxy.scrollTo("bottomAnchor", anchor: .bottom)
            }
        }
    }
}
