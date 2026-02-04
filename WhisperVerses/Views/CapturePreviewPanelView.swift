import SwiftUI

struct CapturePreviewPanelView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedCapture: CapturedVerse?

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
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if appState.capturedImages.isEmpty && appState.detectedVerses.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("Detected verses will appear here")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                VStack(spacing: 0) {
                    // Preview thumbnail of most recent or selected capture
                    if let capture = selectedCapture ?? appState.capturedImages.last {
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

                    List(selection: Binding(
                        get: { selectedCapture?.id },
                        set: { id in selectedCapture = appState.capturedImages.first { $0.id == id } }
                    )) {
                        ForEach(appState.capturedImages.reversed()) { capture in
                            CaptureRow(capture: capture)
                                .tag(capture.id)
                        }

                        // Also show detected verses that haven't been captured yet
                        ForEach(appState.detectedVerses.filter { !$0.status.isSaved }) { verse in
                            HStack {
                                Circle()
                                    .fill(verse.status.dotColor)
                                    .frame(width: 8, height: 8)
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
                                case .failed(let error):
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                        .help(error)
                                default:
                                    EmptyView()
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .background(.background)
    }
}

struct CaptureRow: View {
    let capture: CapturedVerse

    var body: some View {
        HStack {
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
            Text(capture.reference)
                .font(.caption)
            Spacer()
            Text(capture.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

/// Checkerboard background to visualize transparency in PNG previews
struct CheckerboardView: View {
    let size: CGFloat = 8

    var body: some View {
        Canvas { context, canvasSize in
            let rows = Int(canvasSize.height / size) + 1
            let cols = Int(canvasSize.width / size) + 1
            for row in 0..<rows {
                for col in 0..<cols {
                    let isLight = (row + col) % 2 == 0
                    let rect = CGRect(x: CGFloat(col) * size, y: CGFloat(row) * size, width: size, height: size)
                    context.fill(Path(rect), with: .color(isLight ? .white : Color.gray.opacity(0.2)))
                }
            }
        }
    }
}
