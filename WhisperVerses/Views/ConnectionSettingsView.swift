import SwiftUI

struct ConnectionSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        Form {
            Section("ProPresenter") {
                HStack {
                    ConnectionStatusView(isConnected: appState.isProPresenterConnected)
                    TextField("Host", text: $state.proPresenterHost)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 150)
                    Text(":")
                        .foregroundStyle(.secondary)
                    TextField("Port", value: $state.proPresenterPort, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 70)
                    Button("Connect") {
                        Task { await appState.connectToProPresenter() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Section("Bible Library") {
                HStack {
                    TextField("Library name in Pro7", text: $state.bibleLibraryName)
                        .textFieldStyle(.roundedBorder)
                    Button("Index") {
                        Task { await appState.indexBibleLibrary() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let indexer = appState.presentationIndexer {
                    if indexer.isIndexing {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.5)
                            Text("Scanning library...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if let error = indexer.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if indexer.indexedBookCount > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text("\(indexer.indexedBookCount)/66 books found")
                                    .font(.caption)
                                    .foregroundStyle(.green)

                                if !indexer.missingBooks.isEmpty {
                                    Menu {
                                        ForEach(indexer.missingBooks) { book in
                                            Text(book.name)
                                        }
                                    } label: {
                                        Label("\(indexer.missingBooks.count) missing", systemImage: "exclamationmark.triangle")
                                            .font(.caption)
                                    }
                                    .menuStyle(.borderlessButton)
                                    .fixedSize()
                                }
                            }

                            if let loadingBook = indexer.currentlyLoadingBook {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.4)
                                    Text("Loading \(loadingBook)...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else if indexer.indexedVerseCount > 0 {
                                Text("\(indexer.map.loadedCount) books loaded (\(indexer.indexedVerseCount) slides)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Slides loaded on-demand")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
