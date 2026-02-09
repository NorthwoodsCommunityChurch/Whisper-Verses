import Foundation
import Network
import OSLog

private let logger = Logger(subsystem: "com.northwoods.WhisperVerses", category: "HyperDeckClient")

@Observable
final class HyperDeckClient {
    private(set) var isConnected = false
    private(set) var currentTimecode: String = "00:00:00:00"
    private(set) var lastError: String?

    private var connection: NWConnection?
    private var pollingTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5

    private var host: String = ""
    private var port: UInt16 = 9993

    func connect(host: String, port: UInt16 = 9993) {
        self.host = host
        self.port = port
        reconnectAttempts = 0
        lastError = nil

        establishConnection()
    }

    func disconnect() {
        pollingTask?.cancel()
        pollingTask = nil
        connection?.cancel()
        connection = nil

        DispatchQueue.main.async {
            self.isConnected = false
            self.currentTimecode = "00:00:00:00"
        }

        logger.info("HyperDeck disconnected")
    }

    private func establishConnection() {
        let nwHost = NWEndpoint.Host(host)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            logger.error("Invalid port: \(self.port)")
            return
        }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        connection = NWConnection(host: nwHost, port: nwPort, using: params)

        connection?.stateUpdateHandler = { [weak self] state in
            guard let self else { return }

            switch state {
            case .ready:
                logger.info("HyperDeck connected to \(self.host):\(self.port)")
                DispatchQueue.main.async {
                    self.isConnected = true
                    self.lastError = nil
                    self.reconnectAttempts = 0
                }
                self.startPolling()

            case .failed(let error):
                logger.error("HyperDeck connection failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.lastError = error.localizedDescription
                }
                self.attemptReconnect()

            case .cancelled:
                logger.info("HyperDeck connection cancelled")

            default:
                break
            }
        }

        connection?.start(queue: .global(qos: .userInitiated))
    }

    private func attemptReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            logger.warning("Max reconnect attempts reached for HyperDeck")
            return
        }

        reconnectAttempts += 1
        let delay = UInt64(pow(2.0, Double(reconnectAttempts))) * 1_000_000_000 // Exponential backoff

        Task {
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            establishConnection()
        }
    }

    private func startPolling() {
        pollingTask?.cancel()

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.connection != nil else { return }

                await self.requestTransportInfo()

                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
        }
    }

    private func requestTransportInfo() async {
        guard let connection = connection else { return }

        // Send "transport info" command
        let command = "transport info\n"
        guard let data = command.data(using: .utf8) else { return }

        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error = error {
                logger.error("HyperDeck send error: \(error.localizedDescription)")
                return
            }

            // Receive response
            self?.receiveResponse()
        })
    }

    private func receiveResponse() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, error in
            guard let self else { return }

            if let error = error {
                logger.error("HyperDeck receive error: \(error.localizedDescription)")
                return
            }

            if let data = data, let response = String(data: data, encoding: .utf8) {
                self.parseTransportInfo(response)
            }
        }
    }

    private func parseTransportInfo(_ response: String) {
        // HyperDeck protocol response format:
        // 208 transport info:
        // status: record
        // timecode: 01:23:45:12
        // ...

        let lines = response.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.hasPrefix("timecode:") {
                let timecode = trimmed.replacingOccurrences(of: "timecode:", with: "")
                    .trimmingCharacters(in: .whitespaces)

                // Validate timecode format (HH:MM:SS:FF)
                if timecode.range(of: #"^\d{2}:\d{2}:\d{2}:\d{2}$"#, options: .regularExpression) != nil {
                    DispatchQueue.main.async {
                        self.currentTimecode = timecode
                    }
                    return
                }
            }
        }
    }
}
