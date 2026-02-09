import Foundation
import OSLog

private let logger = Logger(subsystem: "com.northwoods.WhisperVerses", category: "HTTPHandler")

struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    var isWebSocketUpgrade: Bool {
        headers["Upgrade"]?.lowercased() == "websocket" &&
        headers["Connection"]?.lowercased().contains("upgrade") == true
    }

    var webSocketKey: String? {
        headers["Sec-WebSocket-Key"]
    }

    var contentType: String? {
        headers["Content-Type"]
    }

    var contentLength: Int? {
        if let lengthStr = headers["Content-Length"] {
            return Int(lengthStr)
        }
        return nil
    }

    static func parse(from data: Data) -> HTTPRequest? {
        guard let headerEnd = data.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) else {
            return nil
        }

        let headerData = data[..<headerEnd.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0])
        let path = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        let body = Data(data[headerEnd.upperBound...])

        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }
}

struct HTTPResponse {
    let statusCode: Int
    let statusText: String
    let headers: [String: String]
    let body: Data

    func toData() -> Data {
        var headerLines = ["HTTP/1.1 \(statusCode) \(statusText)"]

        var responseHeaders = headers
        if responseHeaders["Content-Length"] == nil {
            responseHeaders["Content-Length"] = "\(body.count)"
        }

        for (key, value) in responseHeaders {
            headerLines.append("\(key): \(value)")
        }

        let headerString = headerLines.joined(separator: "\r\n") + "\r\n\r\n"
        var data = Data(headerString.utf8)
        data.append(body)
        return data
    }

    static func ok(body: String, contentType: String = "text/html") -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            statusText: "OK",
            headers: [
                "Content-Type": "\(contentType); charset=utf-8",
                "Cache-Control": "no-cache"
            ],
            body: Data(body.utf8)
        )
    }

    static func ok(data: Data, contentType: String) -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            statusText: "OK",
            headers: [
                "Content-Type": contentType,
                "Cache-Control": "no-cache"
            ],
            body: data
        )
    }

    static func notFound() -> HTTPResponse {
        HTTPResponse(
            statusCode: 404,
            statusText: "Not Found",
            headers: ["Content-Type": "text/plain"],
            body: Data("404 Not Found".utf8)
        )
    }

    static func badRequest(_ message: String = "Bad Request") -> HTTPResponse {
        HTTPResponse(
            statusCode: 400,
            statusText: "Bad Request",
            headers: ["Content-Type": "text/plain"],
            body: Data(message.utf8)
        )
    }

    static func redirect(to url: String) -> HTTPResponse {
        HTTPResponse(
            statusCode: 302,
            statusText: "Found",
            headers: ["Location": url],
            body: Data()
        )
    }
}

enum HTTPHandler {
    static func handleRequest(_ request: HTTPRequest) -> HTTPResponse {
        switch (request.method, request.path) {
        case ("GET", "/"), ("GET", "/index.html"):
            return serveStaticFile("upload.html", contentType: "text/html")

        case ("GET", "/follow"):
            return serveStaticFile("follow.html", contentType: "text/html")

        case ("GET", "/styles.css"):
            return serveStaticFile("styles.css", contentType: "text/css")

        case ("GET", "/app.js"):
            return serveStaticFile("app.js", contentType: "application/javascript")

        case ("POST", "/upload"):
            return handleUpload(request)

        default:
            return .notFound()
        }
    }

    private static func serveStaticFile(_ filename: String, contentType: String) -> HTTPResponse {
        guard let url = Bundle.main.url(forResource: filename, withExtension: nil, subdirectory: "Web") else {
            logger.warning("Static file not found: \(filename)")
            return .notFound()
        }

        do {
            let data = try Data(contentsOf: url)
            return .ok(data: data, contentType: contentType)
        } catch {
            logger.error("Failed to read static file \(filename): \(error.localizedDescription)")
            return .notFound()
        }
    }

    private static func handleUpload(_ request: HTTPRequest) -> HTTPResponse {
        guard let contentType = request.contentType else {
            return .badRequest("Missing Content-Type")
        }

        // Parse multipart form data
        if contentType.contains("multipart/form-data") {
            if let text = parseMultipartFile(request) {
                // Return the extracted text as JSON for the client to send via WebSocket
                let json = ["success": true, "text": text] as [String: Any]
                if let jsonData = try? JSONSerialization.data(withJSONObject: json) {
                    return .ok(data: jsonData, contentType: "application/json")
                }
            }
            return .badRequest("Failed to parse uploaded file")
        }

        return .badRequest("Unsupported Content-Type")
    }

    private static func parseMultipartFile(_ request: HTTPRequest) -> String? {
        guard let contentType = request.contentType,
              let boundaryRange = contentType.range(of: "boundary=") else {
            return nil
        }

        let boundary = "--" + String(contentType[boundaryRange.upperBound...])
        let body = request.body

        // Find file content between boundaries
        guard let boundaryData = boundary.data(using: .utf8),
              let firstBoundary = body.range(of: boundaryData) else {
            return nil
        }

        let afterFirstBoundary = body[firstBoundary.upperBound...]

        // Find the end of headers (blank line)
        guard let headerEnd = afterFirstBoundary.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) else {
            return nil
        }

        // Extract headers to determine filename
        let headerData = afterFirstBoundary[..<headerEnd.lowerBound]
        let headerString = String(data: headerData, encoding: .utf8) ?? ""

        // Get content after headers
        let contentStart = headerEnd.upperBound
        let content = afterFirstBoundary[contentStart...]

        // Find next boundary
        guard let nextBoundary = content.range(of: boundaryData) else {
            return nil
        }

        // Extract file data (minus trailing \r\n)
        var fileData = Data(content[..<nextBoundary.lowerBound])
        if fileData.suffix(2) == Data([0x0D, 0x0A]) {
            fileData = fileData.dropLast(2)
        }

        // Determine file type from filename in headers
        let isDocx = headerString.lowercased().contains(".docx")

        if isDocx {
            return DocumentParser.parseDocx(fileData)
        } else {
            return DocumentParser.parsePlainText(fileData)
        }
    }
}
