import SwiftUI

struct AdvancedSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var isWebServerEnabled = false
    @State private var isHyperDeckEnabled = false

    var body: some View {
        @Bindable var state = appState

        Form {
            Section("Manuscript Server") {
                Toggle("Enable", isOn: $isWebServerEnabled)
                    .onAppear { isWebServerEnabled = appState.webServer.isRunning }
                    .onChange(of: isWebServerEnabled) { _, enabled in
                        if enabled { appState.startWebServer() }
                        else { appState.stopWebServer() }
                    }
                    .onChange(of: appState.webServer.isRunning) { _, running in
                        isWebServerEnabled = running
                    }

                HStack(spacing: 8) {
                    Text("Port:")
                        .foregroundStyle(.secondary)
                    TextField("Port", value: $state.webServerPort, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 70)
                        .disabled(appState.webServer.isRunning)
                        .onChange(of: appState.webServerPort) { _, _ in
                            appState.saveSettings()
                        }

                    if appState.webServer.isRunning {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("\(appState.webServer.connectionCount) client\(appState.webServer.connectionCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if appState.webServer.isRunning {
                        Button("Open") {
                            if let url = URL(string: "http://localhost:\(appState.webServerPort)") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if appState.webServer.isRunning {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(getNetworkURLs(port: appState.webServerPort), id: \.self) { url in
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(url, forType: .string)
                            } label: {
                                HStack(spacing: 4) {
                                    Text(url)
                                        .font(.caption.monospaced())
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tertiary)
                            .help("Click to copy")
                        }
                    }
                }
            }

            Section("HyperDeck") {
                Toggle("Enable", isOn: $isHyperDeckEnabled)
                    .onAppear { isHyperDeckEnabled = appState.hyperDeckClient.isConnected }
                    .onChange(of: isHyperDeckEnabled) { _, enabled in
                        if enabled { appState.connectHyperDeck() }
                        else { appState.disconnectHyperDeck() }
                    }
                    .onChange(of: appState.hyperDeckClient.isConnected) { _, connected in
                        isHyperDeckEnabled = connected
                    }
                    .disabled(appState.hyperDeckHost.isEmpty)

                HStack(spacing: 8) {
                    TextField("IP Address", text: $state.hyperDeckHost)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 150)
                        .disabled(appState.hyperDeckClient.isConnected)
                        .onChange(of: appState.hyperDeckHost) { _, _ in
                            appState.saveSettings()
                        }

                    Text(":")
                        .foregroundStyle(.secondary)

                    TextField("Port", value: $state.hyperDeckPort, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 60)
                        .disabled(appState.hyperDeckClient.isConnected)
                        .onChange(of: appState.hyperDeckPort) { _, _ in
                            appState.saveSettings()
                        }

                    if appState.hyperDeckClient.isConnected {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text(appState.hyperDeckClient.currentTimecode)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = appState.hyperDeckClient.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text("Connect to HyperDeck for timecode-marked clips")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }

    /// Get all network interface URLs for the web server
    private func getNetworkURLs(port: UInt16) -> [String] {
        var urls: [String] = []

        urls.append("http://localhost:\(port)")

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return urls
        }
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
