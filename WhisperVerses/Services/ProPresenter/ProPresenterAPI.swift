import Foundation

/// REST API client for ProPresenter 7 (v7.9+).
/// Provides methods to query libraries, list presentations, and get slide thumbnails.
final class ProPresenterAPI {
    var host: String
    var port: Int

    private var baseURL: String { "http://\(host):\(port)" }

    /// Shared URLSession with short timeouts for responsiveness
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    init(host: String = "127.0.0.1", port: Int = 1025) {
        self.host = host
        self.port = port
    }

    // MARK: - Codable Response Models

    /// Pro7 returns library/item objects with flat uuid, name, index fields.
    struct Library: Codable {
        let uuid: String
        let name: String
        let index: Int
    }

    struct LibraryResponse: Codable {
        let updateType: String?
        let items: [LibraryItem]

        enum CodingKeys: String, CodingKey {
            case updateType = "update_type"
            case items
        }
    }

    struct LibraryItem: Codable {
        let uuid: String
        let name: String
        let index: Int
    }

    // MARK: - Connection

    /// Check if ProPresenter API is reachable.
    func checkConnection() async -> Bool {
        guard let url = URL(string: "\(baseURL)/version") else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Libraries

    /// Get all configured libraries.
    func getLibraries() async throws -> [Library] {
        let data = try await get("/v1/libraries")
        return try JSONDecoder().decode([Library].self, from: data)
    }

    /// Get all items (presentations) in a specific library.
    /// The libraryId can be a UUID, name, or index.
    func getLibraryItems(libraryId: String) async throws -> [LibraryItem] {
        let encoded = libraryId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? libraryId
        let data = try await get("/v1/library/\(encoded)")
        let response = try JSONDecoder().decode(LibraryResponse.self, from: data)
        return response.items
    }

    // MARK: - Slide Thumbnails

    /// Get a slide thumbnail image from a presentation.
    /// Returns raw image data (typically JPEG). The quality parameter controls resolution
    /// (default 400 = 400px on the longest side).
    func getSlideImage(presentationUUID: String, slideIndex: Int, quality: Int = 400) async throws -> Data {
        let encoded = presentationUUID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? presentationUUID
        let data = try await get("/v1/presentation/\(encoded)/thumbnail/\(slideIndex)?quality=\(quality)")
        guard !data.isEmpty else {
            throw APIError.noImageData
        }
        return data
    }

    // MARK: - Live Slide Status

    struct SlideStatus {
        let currentUUID: String
        let currentText: String
    }

    struct SlideIndexStatus {
        let slideIndex: Int
        let presentationUUID: String
        let presentationName: String
    }

    /// Get the current slide status (UUID and text of the live output).
    func getSlideStatus() async -> SlideStatus? {
        guard let url = URL(string: "\(baseURL)/v1/status/slide") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = json["current"] as? [String: Any] else { return nil }
            return SlideStatus(
                currentUUID: current["uuid"] as? String ?? "",
                currentText: current["text"] as? String ?? ""
            )
        } catch {
            return nil
        }
    }

    /// Get the current slide index and presentation info.
    func getSlideIndex() async -> SlideIndexStatus? {
        guard let url = URL(string: "\(baseURL)/v1/presentation/slide_index") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let presIndex = json["presentation_index"] as? [String: Any] else { return nil }
            let slideIndex = presIndex["index"] as? Int ?? 0
            let presId = presIndex["presentation_id"] as? [String: Any]
            return SlideIndexStatus(
                slideIndex: slideIndex,
                presentationUUID: presId?["uuid"] as? String ?? "",
                presentationName: presId?["name"] as? String ?? ""
            )
        } catch {
            return nil
        }
    }

    // MARK: - Trigger (for future use)

    /// Trigger the first cue of a presentation in a library (loads without triggering on output
    /// if the presentation is configured that way). Currently unused — we only read thumbnails.
    func triggerPresentation(libraryId: String, presentationId: String) async throws {
        let libEncoded = libraryId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? libraryId
        let presEncoded = presentationId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? presentationId
        _ = try await get("/v1/library/\(libEncoded)/\(presEncoded)/trigger")
    }

    // MARK: - Private

    private func get(_ path: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestFailed
        }
        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        return data
    }

    // MARK: - Errors

    enum APIError: Error, LocalizedError {
        case invalidURL
        case requestFailed
        case httpError(Int)
        case notConnected
        case noImageData
        case libraryNotFound(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid API URL"
            case .requestFailed: return "API request failed"
            case .httpError(let code): return "HTTP error \(code)"
            case .notConnected: return "Not connected to ProPresenter"
            case .noImageData: return "No image data received"
            case .libraryNotFound(let name): return "Library '\(name)' not found"
            }
        }
    }
}
