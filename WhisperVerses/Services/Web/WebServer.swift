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

    /// Shared manuscript session - all clients see the same content
    private var sharedSession: ManuscriptSession?
    private var sessionFilename: String?
    private var sessionOwnerId: ObjectIdentifier?

    /// Serial queue for thread-safe access to connections and session
    private let connectionQueue = DispatchQueue(label: "com.northwoods.WhisperVerses.connections")

    // Broadcast state from AppState
    private(set) var lastConfirmedText = ""
    private(set) var lastHypothesis = ""
    private(set) var lastAudioLevel: Float = 0

    // HyperDeck integration for clip marking
    var hyperDeckClient: HyperDeckClient?

    // Embedding matcher for manuscript following (set by AppState at startup)
    var embeddingMatcher: EmbeddingMatcher?

    /// Check if a session is currently active
    var hasActiveSession: Bool {
        connectionQueue.sync { sharedSession != nil }
    }

    /// Get the current session filename
    var activeSessionFilename: String? {
        connectionQueue.sync { sessionFilename }
    }

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

        connectionQueue.sync {
            for (_, conn) in connections {
                conn.close()
            }
            connections.removeAll()
            sharedSession = nil
            sessionFilename = nil
            sessionOwnerId = nil
        }

        DispatchQueue.main.async {
            self.isRunning = false
            self.connectionCount = 0
        }

        logger.info("WebServer stopped")
    }

    /// End the current session (can be called from any client or the app)
    func endSession() {
        connectionQueue.async { [self] in
            sharedSession?.reset()
            sharedSession = nil
            sessionFilename = nil
            sessionOwnerId = nil

            // Notify all connected clients that session ended
            for (_, conn) in connections where conn.isWebSocket {
                let message = """
                {"type":"sessionEnded"}
                """
                conn.sendWebSocketText(message)
            }

            logger.info("Session ended")
        }
    }

    func broadcast(confirmedText: String, hypothesis: String, audioLevel: Float) {
        lastConfirmedText = confirmedText
        lastHypothesis = hypothesis
        lastAudioLevel = audioLevel

        // Update shared session and broadcast to all connected clients
        connectionQueue.async { [self] in
            guard let session = sharedSession else { return }

            // Trigger embedding match update in background (for smarter matching)
            let fullTranscript = (confirmedText + " " + hypothesis).trimmingCharacters(in: .whitespaces)
            Task {
                await session.updateEmbeddingMatch(transcript: fullTranscript)
            }

            let update = session.processTranscript(
                confirmedText: confirmedText,
                hypothesis: hypothesis,
                audioLevel: audioLevel
            )

            guard let json = update.toJSON() else { return }

            // Send to all WebSocket clients
            for (_, conn) in connections where conn.isWebSocket {
                conn.sendWebSocketText(json)
            }
        }
    }

    private func handleNewConnection(_ nwConnection: NWConnection) {
        let connection = ClientConnection(connection: nwConnection)
        let id = ObjectIdentifier(connection)

        connectionQueue.sync {
            connections[id] = connection
        }

        DispatchQueue.main.async { [self] in
            connectionQueue.sync {
                self.connectionCount = self.connections.count
            }
        }

        connection.onClose = { [weak self] in
            guard let self = self else { return }
            self.connectionQueue.async {
                self.connections.removeValue(forKey: id)

                // If session owner disconnects, end the session
                if self.sessionOwnerId == id {
                    self.sharedSession?.reset()
                    self.sharedSession = nil
                    self.sessionFilename = nil
                    self.sessionOwnerId = nil
                    logger.info("Session owner disconnected, session ended")
                }

                let count = self.connections.count
                DispatchQueue.main.async {
                    self.connectionCount = count
                }
                logger.info("Connection closed, \(count) remaining")
            }
        }

        connection.onRequest = { [weak self] request in
            self?.handleRequest(request, connection: connection, id: id)
        }

        connection.start()
        connectionQueue.sync {
            logger.info("New connection, \(self.connections.count) total")
        }
    }

    private func handleRequest(_ request: HTTPRequest, connection: ClientConnection, id: ObjectIdentifier) {
        logger.info("Request: \(request.method) \(request.path)")

        // API endpoint: check session status
        if request.path == "/api/session" && request.method == "GET" {
            let status = connectionQueue.sync {
                return [
                    "hasSession": sharedSession != nil,
                    "filename": sessionFilename ?? ""
                ] as [String: Any]
            }
            if let data = try? JSONSerialization.data(withJSONObject: status),
               let json = String(data: data, encoding: .utf8) {
                let response = HTTPResponse(
                    statusCode: 200,
                    statusText: "OK",
                    headers: ["Content-Type": "application/json"],
                    body: Data(json.utf8)
                )
                connection.send(response)
            }
            return
        }

        // API endpoint: end session
        if request.path == "/api/session/end" && request.method == "POST" {
            endSession()
            let response = HTTPResponse(
                statusCode: 200,
                statusText: "OK",
                headers: ["Content-Type": "application/json"],
                body: Data("{\"success\":true}".utf8)
            )
            connection.send(response)
            return
        }

        // WebSocket upgrade
        if request.path == "/ws" && request.isWebSocketUpgrade {
            if let acceptKey = WebSocketHandler.generateAcceptKey(from: request.webSocketKey) {
                connection.upgradeToWebSocket(acceptKey: acceptKey)

                connection.onWebSocketMessage = { [weak self] message in
                    self?.handleWebSocketMessage(message, connectionId: id, connection: connection)
                }

                // If there's an active session, send current state immediately
                connectionQueue.async { [self] in
                    if let session = self.sharedSession {
                        let update = session.processTranscript(
                            confirmedText: self.lastConfirmedText,
                            hypothesis: self.lastHypothesis,
                            audioLevel: self.lastAudioLevel
                        )
                        if let json = update.toJSON() {
                            connection.sendWebSocketText(json)
                        }
                    }
                }

                logger.info("WebSocket upgrade successful")
            }
            return
        }

        // Static file serving
        let response = HTTPHandler.handleRequest(request)
        connection.send(response)
    }

    private func handleWebSocketMessage(_ message: WebSocketMessage, connectionId: ObjectIdentifier, connection: ClientConnection) {
        switch message {
        case .text(let text):
            logger.info("WebSocket text message received: \(text.prefix(100))...")
            if let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let type = json["type"] as? String {
                logger.info("Parsed WebSocket message type: \(type)")

                switch type {
                case "manuscript":
                    handleManuscriptUpload(json: json, connectionId: connectionId, connection: connection)

                case "reset":
                    // Only session owner can reset
                    connectionQueue.async { [self] in
                        if sessionOwnerId == connectionId {
                            endSession()
                        }
                    }

                case "clip":
                    connectionQueue.async { [self] in
                        if let session = sharedSession {
                            handleClipRequest(session: session)
                        }
                    }

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

    private func handleManuscriptUpload(json: [String: Any], connectionId: ObjectIdentifier, connection: ClientConnection) {
        connectionQueue.async { [self] in
            // Check if session already exists
            if sharedSession != nil {
                // Session already active - reject upload
                let errorMsg = """
                {"type":"error","message":"Session already active. Another manuscript is being followed.","filename":"\(sessionFilename ?? "")"}
                """
                connection.sendWebSocketText(errorMsg)
                logger.info("Rejected manuscript upload - session already active")
                return
            }

            // Create new session
            guard let content = json["content"] as? String else {
                logger.error("manuscript message missing content")
                return
            }

            let filename = json["filename"] as? String ?? "Unknown"

            // Use embedding matcher if available, otherwise create a placeholder
            let matcher = self.embeddingMatcher ?? EmbeddingMatcher()
            let session = ManuscriptSession(matcher: matcher)
            session.loadManuscript(content)

            sharedSession = session
            sessionFilename = filename
            sessionOwnerId = connectionId

            logger.info("Manuscript loaded: \(content.count) chars, \(session.chunks.count) chunks, owner set")

            // Build embedding index in background (GPU work)
            Task {
                await session.buildEmbeddingIndex()
            }

            // Send initial state to ALL connected clients
            let update = session.processTranscript(
                confirmedText: lastConfirmedText,
                hypothesis: lastHypothesis,
                audioLevel: lastAudioLevel
            )

            if let responseJson = update.toJSON() {
                for (_, conn) in connections where conn.isWebSocket {
                    conn.sendWebSocketText(responseJson)
                }
                logger.info("Initial state sent to all clients")
            }
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
    private var wsBuffer = Data()  // Buffer for incomplete WebSocket frames

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
        // Set isWebSocket BEFORE sending response to prevent race condition
        // where receiveData() might call itself again before the send completes
        isWebSocket = true

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
                self?.receiveWebSocketFrame()
            } else {
                self?.isWebSocket = false
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
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                self.wsBuffer.append(data)
                logger.debug("WebSocket buffer now \(self.wsBuffer.count) bytes")

                // Process all complete frames in the buffer
                while true {
                    // Reset buffer to contiguous data to avoid slice indexing issues
                    if self.wsBuffer.startIndex != 0 {
                        self.wsBuffer = Data(self.wsBuffer)
                    }

                    guard let message = WebSocketHandler.parseFrame(self.wsBuffer) else {
                        logger.debug("No complete frame in buffer (\(self.wsBuffer.count) bytes)")
                        break // No complete frame available
                    }

                    // Calculate frame size to remove from buffer
                    let frameSize = WebSocketHandler.frameSize(self.wsBuffer)
                    logger.info("Parsed WebSocket frame, size=\(frameSize)")
                    if frameSize > 0 {
                        self.wsBuffer.removeFirst(frameSize)
                    } else {
                        self.wsBuffer.removeAll()
                    }

                    self.onWebSocketMessage?(message)

                    if case .close = message {
                        return
                    }
                }
            }

            if isComplete || error != nil {
                self.onClose?()
            } else {
                self.receiveWebSocketFrame()
            }
        }
    }
}
