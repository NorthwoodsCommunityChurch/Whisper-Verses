import SwiftUI

struct CapturePreviewPanelView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            importBanner
            content
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.Surface.window)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Space.small) {
            Rectangle()
                .fill(Theme.Brand.blue)
                .frame(width: 14, height: 2)
            Text("CATCH FEED")
                .font(Theme.Typography.sectionHeader(10))
                .tracking(1.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Foreground.secondary)

            Spacer()

            if appState.capturedImages.count + appState.detectedVerses.filter({ !$0.status.isSaved }).count > 0 {
                Text(String(format: "%02d", appState.capturedImages.count))
                    .font(Theme.Typography.statusPill(10))
                    .tracking(1.2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Space.small)
                    .padding(.vertical, 2)
                    .background(Theme.Brand.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.med)
    }

    // MARK: - Import banner

    @ViewBuilder
    private var importBanner: some View {
        if appState.documentImportStatus != .idle {
            HStack(spacing: 6) {
                switch appState.documentImportStatus {
                case .parsing:
                    ProgressView().scaleEffect(0.5)
                    Text("Parsing \(appState.lastImportedDocumentName ?? "document")…")
                case .detecting:
                    ProgressView().scaleEffect(0.5)
                    Text("Finding scripture references…")
                case .capturing(let cur, let total):
                    ProgressView().scaleEffect(0.5)
                    Text("Capturing \(cur)/\(total)")
                case .done(let count):
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Brand.green)
                    Text("Imported \(count) verses from \(appState.lastImportedDocumentName ?? "document")")
                case .error(let msg):
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.Status.offline)
                    Text(msg).foregroundStyle(Theme.Status.offline)
                case .idle: EmptyView()
                }
                Spacer()
            }
            .font(Theme.Typography.body(11))
            .foregroundStyle(Theme.Foreground.secondary)
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.small)
            .background(importBannerBg)
        }
    }

    private var importBannerBg: Color {
        switch appState.documentImportStatus {
        case .error: return Theme.Status.offline.opacity(0.08)
        case .done:  return Theme.Brand.green.opacity(0.08)
        default:     return Theme.Brand.lightBlue.opacity(0.05)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if appState.capturedImages.isEmpty && appState.detectedVerses.isEmpty {
            CatchFeedEmpty()
        } else {
            feedList
        }
    }

    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Space.small) {
                let captures = Array(appState.capturedImages.enumerated()).reversed()
                ForEach(Array(captures), id: \.element.id) { (idx, cap) in
                    VerseTile(
                        number: idx + 1,
                        reference: cap.reference,
                        variant: .captured(thumbnail: NSImage(contentsOf: cap.imageURL), savedAt: cap.timestamp)
                    )
                }

                let pending = appState.detectedVerses.filter { !$0.status.isSaved }
                ForEach(pending) { verse in
                    VerseTile(
                        number: 0,
                        reference: verse.reference.displayString,
                        variant: variantForPending(verse)
                    )
                }
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.bottom, Theme.Space.lg)
        }
    }

    private func variantForPending(_ verse: DetectedVerse) -> VerseTile.Variant {
        switch verse.status {
        case .capturing: return .capturing
        case .failed(let e): return .failed(e)
        default: return .next
        }
    }
}
