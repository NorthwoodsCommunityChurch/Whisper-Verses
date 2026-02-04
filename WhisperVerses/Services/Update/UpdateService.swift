import AppKit
import Foundation

@Observable
final class UpdateService {
    // MARK: - Published State

    var updateAvailable = false
    var latestVersion: SemanticVersion?
    var latestReleaseURL: URL?
    var downloadProgress: Double = 0
    var isDownloading = false
    var isApplying = false
    var errorMessage: String?

    // MARK: - Private State

    @ObservationIgnored private var periodicCheckTask: Task<Void, Never>?
    @ObservationIgnored private var lastCheckDate: Date?
    @ObservationIgnored private var cachedRelease: GitHubRelease?

    // MARK: - Constants

    private let repoOwner = "NorthwoodsCommunityChurch"
    private let repoName = "whisper-verses"
    private let assetPrefix = "WhisperVerses-v"
    private let assetSuffix = "-aarch64.zip"
    private let checkInterval: UInt64 = 1800_000_000_000  // 30 minutes in nanoseconds
    private let cacheWindow: TimeInterval = 900            // 15 minutes
    private let initialDelay: UInt64 = 5_000_000_000       // 5 seconds in nanoseconds

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

    // MARK: - Lifecycle

    func startPeriodicChecks() {
        periodicCheckTask?.cancel()
        periodicCheckTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.initialDelay ?? 5_000_000_000)
            guard let self, !Task.isCancelled else { return }

            await self.checkForUpdate()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self.checkInterval)
                guard !Task.isCancelled else { return }
                await self.checkForUpdate()
            }
        }
    }

    func stopPeriodicChecks() {
        periodicCheckTask?.cancel()
        periodicCheckTask = nil
    }

    // MARK: - Update Check

    func checkForUpdate() async {
        if let lastCheck = lastCheckDate,
           Date().timeIntervalSince(lastCheck) < cacheWindow,
           cachedRelease != nil {
            return
        }

        let current = currentAppVersion()

        do {
            let releases = try await fetchReleases()
            lastCheckDate = Date()

            guard let best = releases
                .compactMap({ release -> (GitHubRelease, SemanticVersion)? in
                    guard let version = SemanticVersion(string: release.tagName) else { return nil }
                    guard release.assets.contains(where: { isMatchingAsset($0) }) else { return nil }
                    return (release, version)
                })
                .max(by: { $0.1 < $1.1 })
            else { return }

            cachedRelease = best.0

            await MainActor.run {
                if best.1 > current {
                    self.latestVersion = best.1
                    self.latestReleaseURL = URL(string: best.0.htmlURL)
                    self.updateAvailable = true
                } else {
                    self.updateAvailable = false
                    self.latestVersion = nil
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Update check failed: \(error.localizedDescription)"
            }
        }
    }

    func currentAppVersion() -> SemanticVersion {
        let versionString = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        return SemanticVersion(string: versionString) ?? SemanticVersion(string: "0.0.0")!
    }

    // MARK: - Download and Apply

    func downloadAndApply() async {
        guard let release = cachedRelease,
              let asset = release.assets.first(where: { isMatchingAsset($0) }),
              let downloadURL = URL(string: asset.browserDownloadURL)
        else {
            await MainActor.run { self.errorMessage = "No download URL available" }
            return
        }

        await MainActor.run {
            self.isDownloading = true
            self.downloadProgress = 0
            self.errorMessage = nil
        }

        do {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("WhisperVerses-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let zipURL = tempDir.appendingPathComponent(asset.name)
            try await downloadFile(from: downloadURL, to: zipURL, expectedSize: asset.size)

            await MainActor.run {
                self.isDownloading = false
                self.isApplying = true
            }

            // Unzip using ditto (macOS built-in, handles .app bundles correctly)
            let extractDir = tempDir.appendingPathComponent("extracted")
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-xk", zipURL.path, extractDir.path]
            try ditto.run()
            ditto.waitUntilExit()
            guard ditto.terminationStatus == 0 else {
                throw UpdateError.unzipFailed
            }

            // Find the .app bundle
            let contents = try FileManager.default.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: nil)
            guard let newAppURL = contents.first(where: { $0.pathExtension == "app" }) else {
                throw UpdateError.appNotFoundInZip
            }

            // Validate the bundle has an executable
            let executable = newAppURL.appendingPathComponent("Contents/MacOS/WhisperVerses")
            guard FileManager.default.fileExists(atPath: executable.path) else {
                throw UpdateError.invalidAppBundle
            }

            try applyUpdate(newAppURL: newAppURL, tempDir: tempDir)

        } catch {
            await MainActor.run {
                self.isDownloading = false
                self.isApplying = false
                self.errorMessage = "Update failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Private Helpers

    private func fetchReleases() async throws -> [GitHubRelease] {
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases") else {
            throw UpdateError.networkError("Invalid API URL")
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.networkError("Invalid response")
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 403 {
                throw UpdateError.networkError("GitHub API rate limit exceeded")
            }
            throw UpdateError.networkError("HTTP \(http.statusCode)")
        }

        return try JSONDecoder().decode([GitHubRelease].self, from: data)
    }

    private func downloadFile(from url: URL, to destination: URL, expectedSize: Int) async throws {
        let (asyncBytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.downloadFailed
        }

        let totalSize = expectedSize > 0 ? expectedSize : Int(response.expectedContentLength)
        var data = Data()
        if totalSize > 0 { data.reserveCapacity(totalSize) }

        for try await byte in asyncBytes {
            data.append(byte)
            if totalSize > 0 && data.count % 65536 == 0 {
                let progress = Double(data.count) / Double(totalSize)
                await MainActor.run { self.downloadProgress = min(progress, 1.0) }
            }
        }

        await MainActor.run { self.downloadProgress = 1.0 }
        try data.write(to: destination)
    }

    private func applyUpdate(newAppURL: URL, tempDir: URL) throws {
        let currentAppURL = Bundle.main.bundleURL
        let pid = ProcessInfo.processInfo.processIdentifier

        let script = """
        #!/bin/bash
        # WhisperVerses self-update trampoline
        while kill -0 \(pid) 2>/dev/null; do
            sleep 0.5
        done
        rm -rf "\(currentAppURL.path)"
        mv "\(newAppURL.path)" "\(currentAppURL.path)"
        codesign --force --deep --sign - "\(currentAppURL.path)"
        open "\(currentAppURL.path)"
        rm -rf "\(tempDir.path)"
        """

        let scriptURL = tempDir.appendingPathComponent("update_trampoline.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        process.standardOutput = nil
        process.standardError = nil
        try process.run()

        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }

    private func isMatchingAsset(_ asset: GitHubAsset) -> Bool {
        asset.name.hasPrefix(assetPrefix) && asset.name.hasSuffix(assetSuffix)
    }

    // MARK: - Error Type

    enum UpdateError: Error, LocalizedError {
        case downloadFailed
        case unzipFailed
        case appNotFoundInZip
        case invalidAppBundle
        case networkError(String)

        var errorDescription: String? {
            switch self {
            case .downloadFailed: return "Failed to download update"
            case .unzipFailed: return "Failed to extract update archive"
            case .appNotFoundInZip: return "Update archive does not contain an app bundle"
            case .invalidAppBundle: return "Downloaded app bundle is invalid"
            case .networkError(let msg): return "Network error: \(msg)"
            }
        }
    }

    // MARK: - GitHub API Models

    private struct GitHubRelease: Codable {
        let tagName: String
        let htmlURL: String
        let prerelease: Bool
        let assets: [GitHubAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case prerelease
            case assets
        }
    }

    private struct GitHubAsset: Codable {
        let name: String
        let browserDownloadURL: String
        let size: Int

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case size
        }
    }
}
