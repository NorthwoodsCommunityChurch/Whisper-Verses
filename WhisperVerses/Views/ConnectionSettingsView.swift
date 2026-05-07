import SwiftUI

struct ConnectionSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                proPresenterSection(state: state)
                bibleLibrarySection(state: state)
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Theme.Surface.window)
    }

    // MARK: - ProPresenter section

    private func proPresenterSection(state: AppState) -> some View {
        SettingsSection("ProPresenter", trailing: AnyView(connectionLED)) {
            HStack(spacing: Theme.Space.small) {
                SettingsRow(label: "Host") {
                    SettingsTextField(text: state.binding(\.proPresenterHost),
                                       placeholder: "10.11.1.102",
                                       width: 180,
                                       monospaced: true)
                }
                SettingsRow(label: "Port") {
                    SettingsTextField(text: state.bindingPort(\.proPresenterPort),
                                       placeholder: "1025",
                                       width: 80,
                                       monospaced: true)
                }
                Spacer()
                SettingsActionButton(title: "Connect") {
                    Task { await appState.connectToProPresenter() }
                }
                .padding(.top, Theme.Space.lg)
            }

            if appState.isProPresenterConnected {
                HStack(spacing: 6) {
                    Circle().fill(Theme.Brand.green).frame(width: 6, height: 6)
                    Text("CONNECTED")
                        .font(Theme.Typography.statusPill(9))
                        .tracking(1.5)
                        .foregroundStyle(Theme.Brand.green)
                }
            }
        }
    }

    private var connectionLED: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appState.isProPresenterConnected ? Theme.Brand.green : Theme.Status.offline)
                .frame(width: 8, height: 8)
                .shadow(color: (appState.isProPresenterConnected ? Theme.Brand.green : Theme.Status.offline).opacity(0.6), radius: 4)
            Text(appState.isProPresenterConnected ? "ONLINE" : "OFFLINE")
                .font(Theme.Typography.statusPill(9))
                .tracking(1.5)
                .foregroundStyle(appState.isProPresenterConnected ? Theme.Brand.green : Theme.Status.offline)
        }
    }

    // MARK: - Bible library section

    private func bibleLibrarySection(state: AppState) -> some View {
        SettingsSection("Bible Library") {
            HStack(spacing: Theme.Space.small) {
                SettingsRow(label: "Library Name in Pro7") {
                    SettingsTextField(text: state.binding(\.bibleLibraryName),
                                       placeholder: "Bible NIV",
                                       width: 220)
                }
                Spacer()
                SettingsActionButton(title: "Index") {
                    Task { await appState.indexBibleLibrary() }
                }
                .padding(.top, Theme.Space.lg)
            }

            indexerStatus
        }
    }

    @ViewBuilder
    private var indexerStatus: some View {
        if let indexer = appState.presentationIndexer {
            if indexer.isIndexing {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.5)
                    Text("SCANNING LIBRARY")
                        .font(Theme.Typography.statusPill(9))
                        .tracking(1.5)
                        .foregroundStyle(Theme.Foreground.secondary)
                }
            } else if let error = indexer.errorMessage {
                Text(error)
                    .font(Theme.Typography.body(11))
                    .foregroundStyle(Theme.Status.offline)
            } else if indexer.indexedBookCount > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: Theme.Space.small) {
                        Text(String(format: "%02d/66", indexer.indexedBookCount))
                            .font(Theme.Typography.numeric(16))
                            .foregroundStyle(Theme.Brand.green)
                        Text("BOOKS FOUND")
                            .font(Theme.Typography.statusPill(9))
                            .tracking(1.5)
                            .foregroundStyle(Theme.Foreground.secondary)

                        if !indexer.missingBooks.isEmpty {
                            Spacer()
                            Menu {
                                ForEach(indexer.missingBooks) { book in
                                    Text(book.name)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle")
                                    Text("\(indexer.missingBooks.count) MISSING")
                                        .tracking(1.2)
                                }
                                .font(Theme.Typography.statusPill(9))
                                .foregroundStyle(Theme.Brand.gold)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                    }

                    if let loading = indexer.currentlyLoadingBook {
                        HStack(spacing: 4) {
                            ProgressView().scaleEffect(0.4)
                            Text("Loading \(loading)…")
                                .font(Theme.Typography.body(11))
                                .foregroundStyle(Theme.Foreground.secondary)
                        }
                    } else if indexer.indexedVerseCount > 0 {
                        Text("\(indexer.map.loadedCount) books loaded · \(indexer.indexedVerseCount) slides")
                            .font(Theme.Typography.body(11))
                            .foregroundStyle(Theme.Foreground.tertiary)
                    } else {
                        Text("Slides loaded on demand")
                            .font(Theme.Typography.body(11))
                            .foregroundStyle(Theme.Foreground.tertiary)
                    }
                }
            }
        }
    }
}

// MARK: - AppState binding helpers (local to settings — keeps callsites tidy)

private extension AppState {
    func binding(_ keyPath: ReferenceWritableKeyPath<AppState, String>) -> Binding<String> {
        Binding(get: { self[keyPath: keyPath] }, set: { self[keyPath: keyPath] = $0; self.saveSettings() })
    }
    func bindingPort(_ keyPath: ReferenceWritableKeyPath<AppState, Int>) -> Binding<String> {
        Binding(
            get: { String(self[keyPath: keyPath]) },
            set: { newValue in
                if let v = Int(newValue) { self[keyPath: keyPath] = v; self.saveSettings() }
            }
        )
    }
}
