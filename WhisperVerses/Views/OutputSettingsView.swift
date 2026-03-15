import SwiftUI

struct OutputSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        Form {
            Section("Output Folders") {
                ForEach(appState.outputFolderURLs, id: \.self) { folderURL in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(appState.outputFolderAvailability[folderURL] == true ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)

                        Text(folderURL.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        if appState.outputFolderURLs.count > 1 {
                            Button {
                                appState.removeOutputFolder(folderURL)
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove folder")
                        }
                    }
                }

                Button {
                    addOutputFolder()
                } label: {
                    Label("Add Folder", systemImage: "plus.circle")
                }
                .accessibilityLabel("Add output folder")

                let unavailableCount = appState.outputFolderURLs.filter { appState.outputFolderAvailability[$0] != true }.count
                if unavailableCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("\(unavailableCount) folder\(unavailableCount > 1 ? "s" : "") not available")
                            .font(.caption)
                        Spacer()
                        Button("Retry") {
                            appState.checkOutputFolderAvailability()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Section("Detection") {
                LabeledContent("Confidence Threshold") {
                    HStack {
                        Slider(value: $state.confidenceThreshold, in: 0.3...1.0, step: 0.05)
                        Text("\(Int(appState.confidenceThreshold * 100))%")
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
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
