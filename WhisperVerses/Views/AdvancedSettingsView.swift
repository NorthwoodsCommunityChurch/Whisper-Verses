import SwiftUI

struct AdvancedSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var isWebServerEnabled = false
    @State private var isHyperDeckEnabled = false

    var body: some View {
        @Bindable var state = appState

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                manuscriptServerSection(state: state)
                hyperDeckSection(state: state)
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Theme.Surface.window)
    }

    // MARK: - Manuscript server

    private func manuscriptServerSection(state: AppState) -> some View {
        SettingsSection("Manuscript Server", trailing: AnyView(serverLED)) {
            HStack(spacing: Theme.Space.med) {
                Toggle("", isOn: $isWebServerEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(Theme.Brand.lightBlue)
                    .onAppear { isWebServerEnabled = appState.webServer.isRunning }
                    .onChange(of: isWebServerEnabled) { _, enabled in
                        if enabled { appState.startWebServer() }
                        else { appState.stopWebServer() }
                    }
                    .onChange(of: appState.webServer.isRunning) { _, running in
                        isWebServerEnabled = running
                    }

                SettingsRow(label: "Port") {
                    SettingsTextField(text: state.bindingPort(\.webServerPort),
                                       placeholder: "8080",
                                       width: 80,
                                       disabled: appState.webServer.isRunning,
                                       monospaced: true)
                }

                Spacer()

                if appState.webServer.isRunning {
                    SettingsActionButton(title: "Open", style: .secondary) {
                        if let url = URL(string: "http://localhost:\(appState.webServerPort)") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }

            if appState.webServer.isRunning {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(getNetworkURLs(port: appState.webServerPort), id: \.self) { url in
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url, forType: .string)
                        } label: {
                            HStack(spacing: 6) {
                                Text(url)
                                    .font(.system(size: 11, weight: .regular).monospaced())
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.Foreground.tertiary)
                            }
                            .foregroundStyle(Theme.Foreground.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Click to copy")
                    }
                }
            }
        }
    }

    private var serverLED: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appState.webServer.isRunning ? Theme.Brand.green : Theme.Foreground.tertiary)
                .frame(width: 8, height: 8)
                .shadow(color: appState.webServer.isRunning ? Theme.Brand.green.opacity(0.6) : .clear, radius: 4)
            if appState.webServer.isRunning {
                Text("\(appState.webServer.connectionCount) CLIENT\(appState.webServer.connectionCount == 1 ? "" : "S")")
                    .font(Theme.Typography.statusPill(9))
                    .tracking(1.5)
                    .foregroundStyle(Theme.Brand.green)
            } else {
                Text("OFF")
                    .font(Theme.Typography.statusPill(9))
                    .tracking(1.5)
                    .foregroundStyle(Theme.Foreground.tertiary)
            }
        }
    }

    // MARK: - HyperDeck

    private func hyperDeckSection(state: AppState) -> some View {
        SettingsSection("HyperDeck", trailing: AnyView(hyperDeckLED)) {
            HStack(spacing: Theme.Space.med) {
                Toggle("", isOn: $isHyperDeckEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(Theme.Brand.lightBlue)
                    .onAppear { isHyperDeckEnabled = appState.hyperDeckClient.isConnected }
                    .onChange(of: isHyperDeckEnabled) { _, enabled in
                        if enabled { appState.connectHyperDeck() }
                        else { appState.disconnectHyperDeck() }
                    }
                    .onChange(of: appState.hyperDeckClient.isConnected) { _, connected in
                        isHyperDeckEnabled = connected
                    }
                    .disabled(appState.hyperDeckHost.isEmpty)

                SettingsRow(label: "IP Address") {
                    SettingsTextField(text: state.binding(\.hyperDeckHost),
                                       placeholder: "10.10.11.50",
                                       width: 160,
                                       disabled: appState.hyperDeckClient.isConnected,
                                       monospaced: true)
                }
                SettingsRow(label: "Port") {
                    SettingsTextField(text: state.bindingPort(\.hyperDeckPort),
                                       placeholder: "9993",
                                       width: 70,
                                       disabled: appState.hyperDeckClient.isConnected,
                                       monospaced: true)
                }
                Spacer()
            }

            if appState.hyperDeckClient.isConnected {
                Text("Timecode · \(appState.hyperDeckClient.currentTimecode)")
                    .font(Theme.Typography.numeric(14))
                    .foregroundStyle(Theme.Brand.green)
            }

            if let error = appState.hyperDeckClient.lastError {
                Text(error)
                    .font(Theme.Typography.body(11))
                    .foregroundStyle(Theme.Status.offline)
            }

            Text("Connect to HyperDeck for timecode-marked clips")
                .font(Theme.Typography.body(11))
                .foregroundStyle(Theme.Foreground.tertiary)
        }
    }

    private var hyperDeckLED: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appState.hyperDeckClient.isConnected ? Theme.Brand.green : Theme.Foreground.tertiary)
                .frame(width: 8, height: 8)
                .shadow(color: appState.hyperDeckClient.isConnected ? Theme.Brand.green.opacity(0.6) : .clear, radius: 4)
            Text(appState.hyperDeckClient.isConnected ? "ONLINE" : "OFFLINE")
                .font(Theme.Typography.statusPill(9))
                .tracking(1.5)
                .foregroundStyle(appState.hyperDeckClient.isConnected ? Theme.Brand.green : Theme.Foreground.tertiary)
        }
    }

    /// Get all network interface URLs for the web server.
    private func getNetworkURLs(port: UInt16) -> [String] {
        var urls: [String] = []
        urls.append("http://localhost:\(port)")

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return urls }
        defer { freeifaddrs(ifaddr) }

        var ptr = firstAddr
        while true {
            let interface = ptr.pointee
            let family = interface.ifa_addr.pointee.sa_family
            if family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name != "lo0" {
                    var addr = interface.ifa_addr.pointee
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(
                        &addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count),
                        nil, 0, NI_NUMERICHOST
                    ) == 0 {
                        let ip = String(cString: hostname)
                        if !ip.hasPrefix("169.254.") {
                            urls.append("http://\(ip):\(port)")
                        }
                    }
                }
            }
            guard let next = interface.ifa_next else { break }
            ptr = next
        }
        return urls
    }
}

private extension AppState {
    func binding(_ keyPath: ReferenceWritableKeyPath<AppState, String>) -> Binding<String> {
        Binding(get: { self[keyPath: keyPath] }, set: { self[keyPath: keyPath] = $0; self.saveSettings() })
    }
    func bindingPort<T: BinaryInteger & LosslessStringConvertible>(_ keyPath: ReferenceWritableKeyPath<AppState, T>) -> Binding<String> {
        Binding(
            get: { String(self[keyPath: keyPath]) },
            set: { newValue in
                if let v = T(newValue) { self[keyPath: keyPath] = v; self.saveSettings() }
            }
        )
    }
}
