import SwiftUI

struct OutputSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                outputFoldersSection
                detectionSection(state: state)
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Theme.Surface.window)
    }

    // MARK: - Output folders

    private var outputFoldersSection: some View {
        SettingsSection("Output Folders") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(appState.outputFolderURLs, id: \.self) { folderURL in
                    folderRow(folderURL)
                }
            }

            HStack {
                SettingsActionButton(title: "Add Folder") { addOutputFolder() }
                Spacer()
                let unavailableCount = appState.outputFolderURLs.filter { appState.outputFolderAvailability[$0] != true }.count
                if unavailableCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Brand.gold)
                        Text("\(unavailableCount) UNAVAILABLE")
                            .font(Theme.Typography.statusPill(9))
                            .tracking(1.5)
                            .foregroundStyle(Theme.Brand.gold)
                        SettingsActionButton(title: "Retry", style: .secondary) {
                            appState.checkOutputFolderAvailability()
                        }
                    }
                }
            }
        }
    }

    private func folderRow(_ folderURL: URL) -> some View {
        HStack(spacing: Theme.Space.small) {
            Circle()
                .fill(appState.outputFolderAvailability[folderURL] == true ? Theme.Brand.green : Theme.Status.offline)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            Text(folderURL.path)
                .font(.system(size: 11, weight: .regular).monospaced())
                .foregroundStyle(Theme.Foreground.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if appState.outputFolderURLs.count > 1 {
                Button {
                    appState.removeOutputFolder(folderURL)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Foreground.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove folder")
            }
        }
        .padding(.horizontal, Theme.Space.small)
        .padding(.vertical, 6)
        .background(Theme.Surface.window)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    // MARK: - Detection

    private func detectionSection(state: AppState) -> some View {
        SettingsSection("Detection") {
            SettingsRow(label: "Confidence Threshold") {
                HStack(spacing: Theme.Space.med) {
                    Slider(value: state.binding(\.confidenceThreshold), in: 0.3...1.0, step: 0.05)
                        .tint(Theme.Brand.lightBlue)
                    Text("\(Int(appState.confidenceThreshold * 100))%")
                        .font(Theme.Typography.numeric(13))
                        .foregroundStyle(Theme.Foreground.primary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
    }

    private func addOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Add Output Folder"
        if panel.runModal() == .OK, let url = panel.url {
            appState.addOutputFolder(url)
        }
    }
}

private extension AppState {
    func binding(_ keyPath: ReferenceWritableKeyPath<AppState, Double>) -> Binding<Double> {
        Binding(get: { self[keyPath: keyPath] }, set: { self[keyPath: keyPath] = $0; self.saveSettings() })
    }
}
