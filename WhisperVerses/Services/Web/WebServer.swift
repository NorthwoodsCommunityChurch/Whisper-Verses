import Foundation
import Network
import OSLog

private let logger = Logger(subsystem: "com.northwoods.WhisperVerses", category: "WebServer")

@Observable
final class WebServer {
    private(set) var isRunning = false
    private(set) var port: UInt16 = 8080
    private(set) var connectionCount = 0

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: ClientConnection] = [:]
    private var sessions: [ObjectIdentifier: ManuscriptSession] = [:]

    // Broadcast state from AppState
    private(set) var lastConfirmedText = ""
    private(set) var lastHypothesis = ""
    private(set) var lastAudioLevel: Float = 0

    // HyperDeck integration for clip marking
    var hyperDeckClient: HyperDeckClient?

    func start(port: UInt16 = 8080) {
        guard !isRunning else { return }

        self.port = port

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true

            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                logger.error("Invalid port: \(port)")
                return
            }

            listener = try NWListener(using: params, on: nwPort)

            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    logger.info("WebServer listening on port \(port)")
                    DispatchQueue.main.async {
                        self?.isRunning = true
                    }
                case .failed(let error):
                    logger.error("WebServer failed: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self?.isRunning = false
                    }
                case .cancelled:
                    logger.info("WebServer cancelled")
                    DispatchQueue.main.async {
                        self?.isRunning = false
                    }
                default:
                    break
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }

            listener?.start(queue: .global(qos: .userInitiated))

        } catch {
            logger.error("Failed to start WebServer: \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil

        for (_, conn) in connections {
            conn.close()
        }
        connections.removeAll()
        sessions.removeAll()

        DispatchQueue.main.async {
            self.isRunning = false
            self.connectionCount = 0
        }

        logger.info("WebServer stopped")
    }

    func broadcast(confirmedText: String, hypothesis: String, audioLevel: Float) {
        lastConfirmedText = confirmedText
        lastHypothesis = hypothesis
        lastAudioLevel = audioLevel

        // Update all sessions and send WebSocket messages
        for (id, session) in sessions {
            guard let conn = connections[id], conn.isWebSocket else { continue }

            let update = session.processTranscript(
                confirmedText: confirmedText,
                hypothesis: hypothesis,
                audioLevel: audioLevel
            )

            if let json = update.toJSON() {
                conn.sendWebSocketText(json)
            }
        }
    }

    private func handleNewConnection(_ nwConnection: NWConnection) {
        let connection = ClientConnection(connection: nwConnection)
        let id = ObjectIdentifier(connection)

        connections[id] = connection

        DispatchQueue.main.async {
            self.connectionCount = self.connections.count
        }

        connection.onClose = { [weak self] in
            self?.connections.removeValue(forKey: id)
            self?.sessions.removeValue(forKey: id)
            DispatchQueue.main.async {
                self?.connectionCount = self?.connections.count ?? 0
            }
            logger.info("Connection closed, \(self?.connections.count ?? 0) remaining")
        }

        connection.onRequest = { [weak self] request in
            self?.handleRequest(request, connection: connection, id: id)
        }

        connection.start()
        logger.info("New connection, \(self.connections.count) total")
    }

    private func handleRequest(_ request: HTTPRequest, connection: ClientConnection, id: ObjectIdentifier) {
        logger.info("Request: \(request.method) \(request.path)")

        // WebSocket upgrade
        if request.path == "/ws" && request.isWebSocketUpgrade {
            if let acceptKey = WebSocketHandler.generateAcceptKey(from: request.webSocketKey) {
                connection.upgradeToWebSocket(acceptKey: acceptKey)

                // Create session for this connection
                sessions[id] = ManuscriptSession()

                connection.onWebSocketMessage = { [weak self] message in
                    self?.handleWebSocketMessage(message, session: self?.sessions[id], connection: connection)
                }

                logger.info("WebSocket upgrade successful")
            }
            return
        }

        // Static file serving
        let response = HTTPHandler.handleRequest(request)
        connection.send(response)
    }

    private func handleWebSocketMessage(_ message: WebSocketMessage, session: ManuscriptSession?, connection: ClientConnection) {
        guard let session = session else { return }

        switch message {
        case .text(let text):
            if let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let type = json["type"] as? String {

                switch type {
                case "manuscript":
                    if let content = json["content"] as? String {
                        session.loadManuscript(content)
                        logger.info("Manuscript loaded: \(content.prefix(50))...")

                        // Send initial state
                        let update = session.processTranscript(
                            confirmedText: lastConfirmedText,
                            hypothesis: lastHypothesis,
                            audioLevel: lastAudioLevel
                        )
                        if let responseJson = update.toJSON() {
                            connection.sendWebSocketText(responseJson)
                        }
                    }

                case "reset":
                    session.reset()
                    logger.info("Session reset")

                case "clip":
                    handleClipRequest(session: session)

                default:
                    logger.warning("Unknown WebSocket message type: \(type)")
                }
            }

        case .binary(_):
            logger.warning("Unexpected binary WebSocket message")

        case .close:
            connection.close()
        }
    }

    private func handleClipRequest(session: ManuscriptSession) {
        let timecode = hyperDeckClient?.currentTimecode ?? "00:00:00:00"
        let snippet = session.currentSnippet

        ClipManager.saveClip(timecode: timecode, manuscriptSnippet: snippet)
        logger.info("Clip saved at \(timecode), position \(session.currentPosition)")
    }
}

// MARK: - Client Connection

final class ClientConnection {
    private let connection: NWConnection
    private(set) var isWebSocket = false

    var onClose: (() -> Void)?
    var onRequest: ((HTTPRequest) -> Void)?
    var onWebSocketMessage: ((WebSocketMessage) -> Void)?

    private var receivedData = Data()

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveData()
            case .failed, .cancelled:
                self?.onClose?()
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
    }

    func close() {
        connection.cancel()
    }

    func send(_ response: HTTPResponse) {
        connection.send(content: response.toData(), completion: .contentProcessed { [weak self] error in
            if let error = error {
                logger.error("Send error: \(error.localizedDescription)")
                self?.close()
            }
        })
    }

    func upgradeToWebSocket(acceptKey: String) {
        let response = HTTPResponse(
            statusCode: 101,
            statusText: "Switching Protocols",
            headers: [
                "Upgrade": "websocket",
                "Connection": "Upgrade",
                "Sec-WebSocket-Accept": acceptKey
            ],
            body: Data()
        )

        connection.send(content: response.toData(), completion: .contentProcessed { [weak self] error in
            if error == nil {
                self?.isWebSocket = true
                self?.receiveWebSocketFrame()
            }
        })
    }

    func sendWebSocketText(_ text: String) {
        guard isWebSocket, let data = text.data(using: .utf8) else { return }
        let frame = WebSocketHandler.createTextFrame(data)
        connection.send(content: frame, completion: .contentProcessed { error in
            if let error = error {
                logger.error("WebSocket send error: \(error.localizedDescription)")
            }
        })
    }

    private func receiveData() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                self?.receivedData.append(data)
                self?.tryParseHTTPRequest()
            }

            if isComplete || error != nil {
                self?.onClose?()
            } else if !self!.isWebSocket {
                self?.receiveData()
            }
        }
    }

    private func tryParseHTTPRequest() {
        if let request = HTTPRequest.parse(from: receivedData) {
            receivedData.removeAll()
            onRequest?(request)
        }
    }

    private func receiveWebSocketFrame() {
        connection.receive(minimumIncompleteLength: 2, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                if let message = WebSocketHandler.parseFrame(data) {
                    self?.onWebSocketMessage?(message)

                    if case .close = message {
                        return
                    }
                }
            }

            if isComplete || error != nil {
                self?.onClose?()
            } else {
                self?.receiveWebSocketFrame()
            }
        }
    }
}
