import SwiftUI

struct UpdateBannerView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let service = appState.updateService

        if service.isApplying {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.5)
                Text("Applying update...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        } else if service.isDownloading {
            ProgressView(value: service.downloadProgress) {
                Text("Downloading update (\(Int(service.downloadProgress * 100))%)...")
                    .font(.caption)
            }
            .padding(8)
            .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        } else if service.updateAvailable, let version = service.latestVersion {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Update Available: v\(version)")
                        .font(.caption)
                        .bold()
                    Text("Current: v\(service.currentAppVersion())")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Update") {
                    Task { await service.downloadAndApply() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(8)
            .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }

        if let error = service.errorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
                Text(error)
                    .font(.caption2)
                    .lineLimit(2)
                Spacer()
                Button {
                    service.errorMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(8)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
