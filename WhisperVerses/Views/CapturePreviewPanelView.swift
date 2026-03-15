import SwiftUI

struct CapturePreviewPanelView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedCaptureID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Pro7 Capture")
                    .font(.headline)
                Spacer()
                Text("\(appState.capturedImages.count) captured")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.03))

            // Document import progress banner
            if appState.documentImportStatus != .idle {
                HStack(spacing: 6) {
                    switch appState.documentImportStatus {
                    case .parsing:
                        ProgressView()
                            .scaleEffect(0.5)
                        Text("Parsing \(appState.lastImportedDocumentName ?? "document")...")
                            .font(.caption)
                    case .detecting:
                        ProgressView()
                            .scaleEffect(0.5)
                        Text("Finding scripture references...")
                            .font(.caption)
                    case .capturing(let current, let total):
                        ProgressView()
                            .scaleEffect(0.5)
                        Text("Capturing verse \(current) of \(total)...")
                            .font(.caption)
                    case .done(let count):
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Imported \(count) verses from \(appState.lastImportedDocumentName ?? "document")")
                            .font(.caption)
                    case .error(let message):
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    case .idle:
                        EmptyView()
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(importBannerBackground(appState.documentImportStatus))

                Divider()
            }

            if appState.capturedImages.isEmpty && appState.detectedVerses.isEmpty {
                ContentUnavailableView(
                    "No Captures Yet",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Detected verses will appear here")
                )
            } else {
                VStack(spacing: 0) {
                    // Preview thumbnail of most recent or selected capture
                    if let capture = selectedCaptureID.flatMap({ id in appState.capturedImages.first { $0.id == id } }) ?? appState.capturedImages.last {
                        VStack(spacing: 4) {
                            if let image = NSImage(contentsOf: capture.imageURL) {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 100)
                                    .background(CheckerboardView())
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            Text(capture.reference)
                                .font(.caption)
                                .bold()
                            Text("Saved: \(capture.filename)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.top, 4)
                    }

                    Divider()
                        .padding(.top, 4)

                    // Recent captures list
                    Text("Recent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 4)

                    List(selection: $selectedCaptureID) {
                        ForEach(appState.capturedImages.reversed()) { capture in
                            CaptureRow(capture: capture)
                                .tag(capture.id)
                        }

                        // Also show detected verses that haven't been captured yet
                        ForEach(appState.detectedVerses.filter { !$0.status.isSaved }) { verse in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Circle()
                                        .fill(verse.status.dotColor)
                                        .frame(width: 8, height: 8)
                                        .accessibilityHidden(true)
                                    Text(verse.reference.displayString)
                                        .font(.caption)
                                        .foregroundStyle(verse.status.isDuplicate ? .tertiary : .primary)
                                    Spacer()
                                    switch verse.status {
                                    case .capturing:
                                        ProgressView()
                                            .scaleEffect(0.5)
                                    case .duplicate:
                                        Text("dup")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    case .failed:
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.red)
                                    default:
                                        EmptyView()
                                    }
                                }
                                // Show error message directly for failed status
                                if case .failed(let error) = verse.status {
                                    Text(error)
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.white.opacity(0.03))
    }

    private func importBannerBackground(_ status: AppState.DocumentImportStatus) -> Color {
        switch status {
        case .error: return Color.red.opacity(0.1)
        case .done: return Color.green.opacity(0.1)
        default: return Color.accentColor.opacity(0.05)
        }
    }
}
