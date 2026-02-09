import CoreAudio
import Foundation
import os.log
import SwiftUI

private let logger = Logger(subsystem: "com.whisperverses", category: "AppState")

@Observable
final class AppState {
    // MARK: - Audio
    var selectedAudioDeviceID: AudioDeviceID?
    var availableAudioDevices: [AudioDevice] = []
    var audioLevel: Float = 0.0
    var isListening = false

    // MARK: - Transcription
    var confirmedSegments: [TranscriptSegment] = []
    var currentHypothesis: String = ""
    var isModelLoaded = false
    var isModelLoading = false
    var modelDownloadProgress: Double = 0.0

    // MARK: - Verse Detection
    var detectedVerses: [DetectedVerse] = []

    // MARK: - ProPresenter
    var proPresenterHost: String = "127.0.0.1"
    var proPresenterPort: Int = 1025
    var isProPresenterConnected = false
    var bibleLibraryName: String = "Default"

    // MARK: - Output
    private static let defaultOutputFolder: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        .appendingPathComponent("Whisper Drops", isDirectory: true)
    var outputFolderURLs: [URL] = [defaultOutputFolder]
    var outputFolderAvailability: [URL: Bool] = [:]  // Tracks which folders are writable
    var capturedImages: [CapturedVerse] = []
    var capturedVerseKeys: Set<String> = []  // Tracks individual verses already captured (e.g., "John 3:16")
    var nextSequenceNumbers: [URL: Int] = [:]  // Per-folder sequence numbers

    // MARK: - Settings
    var confidenceThreshold: Double = 0.7
    var hasCompletedOnboarding: Bool = false
    var inputGain: Float = 1.0  // 0.5 to 3.0, 1.0 is unity gain

    // MARK: - Error Display
    var errorMessage: String?
    @ObservationIgnored private var errorDismissTask: Task<Void, Never>?

    // MARK: - Services
    var audioDeviceManager = AudioDeviceManager()
    var transcriptionService: TranscriptionService?
    var verseDetector = VerseDetector()
    var proPresenterAPI = ProPresenterAPI()
    var presentationIndexer: PresentationIndexer?
    var updateService = UpdateService()
    var webServer = WebServer()
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var hypothesisPollTask: Task<Void, Never>?

    // MARK: - Web Server Settings
    var isWebServerEnabled: Bool = false
    var webServerPort: UInt16 = 8080

    // MARK: - HyperDeck Settings
    var hyperDeckClient = HyperDeckClient()
    var hyperDeckHost: String = ""
    var hyperDeckPort: UInt16 = 9993
    var isHyperDeckEnabled: Bool = false

    init() {
        loadSettings()
        ensureOutputFolders()
        checkOutputFolderAvailability()
        updateService.startPeriodicChecks()
    }

    private func ensureOutputFolders() {
        for folderURL in outputFolderURLs {
            try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
    }

    /// Check if output folders are writable (important for SMB shares that may not be mounted)
    func checkOutputFolderAvailability() {
        let fm = FileManager.default

        for folderURL in outputFolderURLs {
            // First check if path exists
            var isDirectory: ObjCBool = false
            let exists = fm.fileExists(atPath: folderURL.path, isDirectory: &isDirectory)

            if !exists || !isDirectory.boolValue {
                // Try to create it
                do {
                    try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
                    outputFolderAvailability[folderURL] = true
                    logger.info("Output folder created: \(folderURL.path)")
                } catch {
                    outputFolderAvailability[folderURL] = false
                    logger.warning("Output folder not available: \(folderURL.path) - \(error.localizedDescription)")
                }
                continue
            }

            // Try to write a test file to verify writability
            let testFile = folderURL.appendingPathComponent(".writetest")
            do {
                try Data().write(to: testFile)
                try fm.removeItem(at: testFile)
                outputFolderAvailability[folderURL] = true
                logger.info("Output folder is writable: \(folderURL.path)")
            } catch {
                outputFolderAvailability[folderURL] = false
                logger.warning("Output folder not writable: \(folderURL.path) - \(error.localizedDescription)")
            }
        }
    }

    func clearOutputFolders() {
        let fm = FileManager.default
        for folderURL in outputFolderURLs {
            if let files = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) {
                for file in files where file.pathExtension == "png" {
                    try? fm.removeItem(at: file)
                }
            }
            nextSequenceNumbers[folderURL] = 1
        }
        capturedImages.removeAll()
        capturedVerseKeys.removeAll()
        detectedVerses.removeAll()
    }

    /// Add a new output folder
    func addOutputFolder(_ url: URL) {
        guard !outputFolderURLs.contains(url) else { return }
        outputFolderURLs.append(url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        checkOutputFolderAvailability()
        saveSettings()
    }

    /// Remove an output folder
    func removeOutputFolder(_ url: URL) {
        outputFolderURLs.removeAll { $0 == url }
        outputFolderAvailability.removeValue(forKey: url)
        nextSequenceNumbers.removeValue(forKey: url)
        saveSettings()
    }

    // MARK: - Settings Persistence

    private func loadSettings() {
        let defaults = UserDefaults.standard
        if let host = defaults.string(forKey: "proPresenterHost") {
            proPresenterHost = host
        }
        let port = defaults.integer(forKey: "proPresenterPort")
        if port > 0 { proPresenterPort = port }
        if let name = defaults.string(forKey: "bibleLibraryName"), name != "Bible KJV" {
            bibleLibraryName = name
        }
        // Load output folders - migrate from old single-folder format if needed
        if let paths = defaults.stringArray(forKey: "outputFolderPaths"), !paths.isEmpty {
            outputFolderURLs = paths.map { URL(fileURLWithPath: $0) }
        } else if let oldPath = defaults.string(forKey: "outputFolderPath") {
            // Migrate from old single-folder format
            outputFolderURLs = [URL(fileURLWithPath: oldPath)]
        }
        let threshold = defaults.double(forKey: "confidenceThreshold")
        if threshold > 0 { confidenceThreshold = threshold }
        let deviceID = defaults.integer(forKey: "selectedAudioDeviceID")
        if deviceID > 0 { selectedAudioDeviceID = AudioDeviceID(deviceID) }
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        let savedGain = defaults.float(forKey: "inputGain")
        if savedGain > 0 { inputGain = savedGain }
        // Sync to the static property used by audio processor
        ThreadSafeAudioProcessor.inputGain = inputGain

        // Web server settings
        let savedWebPort = defaults.integer(forKey: "webServerPort")
        if savedWebPort > 0 { webServerPort = UInt16(savedWebPort) }
        isWebServerEnabled = defaults.bool(forKey: "webServerEnabled")
        if isWebServerEnabled {
            webServer.hyperDeckClient = hyperDeckClient
            webServer.start(port: webServerPort)
        }

        // HyperDeck settings
        if let savedHyperDeckHost = defaults.string(forKey: "hyperDeckHost") {
            hyperDeckHost = savedHyperDeckHost
        }
        let savedHyperDeckPort = defaults.integer(forKey: "hyperDeckPort")
        if savedHyperDeckPort > 0 { hyperDeckPort = UInt16(savedHyperDeckPort) }
        isHyperDeckEnabled = defaults.bool(forKey: "hyperDeckEnabled")
        if isHyperDeckEnabled && !hyperDeckHost.isEmpty {
            hyperDeckClient.connect(host: hyperDeckHost, port: hyperDeckPort)
        }
    }

    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(proPresenterHost, forKey: "proPresenterHost")
        defaults.set(proPresenterPort, forKey: "proPresenterPort")
        defaults.set(bibleLibraryName, forKey: "bibleLibraryName")
        // Save output folders as array of paths
        let paths = outputFolderURLs.map { $0.path }
        defaults.set(paths, forKey: "outputFolderPaths")
        defaults.set(confidenceThreshold, forKey: "confidenceThreshold")
        if let deviceID = selectedAudioDeviceID {
            defaults.set(Int(deviceID), forKey: "selectedAudioDeviceID")
        }
        defaults.set(inputGain, forKey: "inputGain")

        // Web server settings
        defaults.set(Int(webServerPort), forKey: "webServerPort")
        defaults.set(isWebServerEnabled, forKey: "webServerEnabled")

        // HyperDeck settings
        defaults.set(hyperDeckHost, forKey: "hyperDeckHost")
        defaults.set(Int(hyperDeckPort), forKey: "hyperDeckPort")
        defaults.set(isHyperDeckEnabled, forKey: "hyperDeckEnabled")
    }

    // MARK: - Error Display

    func showError(_ message: String) {
        errorMessage = message
        errorDismissTask?.cancel()
        errorDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, !Task.isCancelled else { return }
            await MainActor.run { self.errorMessage = nil }
        }
    }

    func dismissError() {
        errorDismissTask?.cancel()
        errorMessage = nil
    }

    // MARK: - Onboarding

    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }

    // MARK: - Listening

    func toggleListening() async {
        if isListening {
            stopListening()
        } else {
            await startListening()
        }
    }

    func startListening() async {
        // Check if output folder is available (SMB share might not be mounted)
        checkOutputFolderAvailability()

        // Auto-index if connected but not yet indexed
        if isProPresenterConnected,
           presentationIndexer == nil || presentationIndexer?.map.isEmpty == true {
            await indexBibleLibrary()
        }

        if transcriptionService == nil {
            let service = TranscriptionService()
            transcriptionService = service

            let detector = verseDetector
            service.onSegmentConfirmed = { [weak self] segment in
                guard let self else { return }

                // Detect verses in current segment only (for highlighting)
                let detected = detector.detect(in: segment.text)
                var detectedKeys = Set(detected.map { $0.reference.displayString })

                // Also check combined recent segments for cross-segment references
                // (e.g., "2 Peter 1" in one segment, "verses 20 to 21" in next)
                // These are tracked for capture but NOT added to segment's references
                // because the segment doesn't contain the complete reference text
                var crossSegmentDetected: [DetectedVerse] = []
                if !self.confirmedSegments.isEmpty {
                    let recentCount = min(2, self.confirmedSegments.count)
                    let recentTexts = self.confirmedSegments.suffix(recentCount).map { $0.text }
                    let combinedText = (recentTexts + [segment.text]).joined(separator: " ")

                    let combinedDetected = detector.detect(in: combinedText)
                    for verse in combinedDetected {
                        let key = verse.reference.displayString
                        // Only add if not already detected in current segment
                        if !detectedKeys.contains(key) {
                            logger.info("Cross-segment detection: Found '\(key)' spanning segments")
                            crossSegmentDetected.append(verse)
                            detectedKeys.insert(key)
                        }
                    }
                }

                // Only highlight segments that contain complete verse references
                let enrichedSegment = TranscriptSegment(
                    text: segment.text,
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    isConfirmed: segment.isConfirmed,
                    detectedReferences: detected.map { $0.reference }
                )
                self.confirmedSegments.append(enrichedSegment)

                // Process all detected verses (both in-segment and cross-segment) for capture
                let allDetected = detected + crossSegmentDetected
                for verse in allDetected {
                    self.detectedVerses.append(verse)
                    if self.isProPresenterConnected,
                       let indexer = self.presentationIndexer,
                       !indexer.map.isEmpty {
                        Task {
                            await self.captureVerseSlide(verse)
                        }
                    }
                }
            }

            // Poll TranscriptionService progress during model loading
            isModelLoading = true
            let progressTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                    guard let self, !Task.isCancelled else { return }
                    await MainActor.run {
                        self.modelDownloadProgress = service.modelDownloadProgress
                    }
                }
            }

            await service.loadModel()
            progressTask.cancel()

            isModelLoaded = service.isModelLoaded
            isModelLoading = service.isModelLoading
            modelDownloadProgress = service.modelDownloadProgress

            if let error = service.errorMessage {
                showError(error)
                return
            }
        }

        guard let service = transcriptionService, service.isModelLoaded else {
            showError("Whisper model not loaded. Check your internet connection and try again.")
            return
        }

        // Stop our level monitoring to avoid AVAudioEngine conflicts with WhisperKit
        audioDeviceManager.stopLevelMonitoring()

        await service.startListening()

        await MainActor.run {
            self.isListening = service.isListening
        }

        if let error = service.errorMessage {
            showError(error)
        }

        // Poll hypothesis text and audio level for live partial results
        if isListening {
            hypothesisPollTask?.cancel()
            hypothesisPollTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
                    guard let self, !Task.isCancelled else { return }
                    await MainActor.run {
                        self.currentHypothesis = service.currentText
                        // Get audio level from WhisperKit's processor during transcription
                        self.audioLevel = ThreadSafeAudioProcessor.currentRMSLevel

                        // Broadcast to web clients if server is running
                        if self.webServer.isRunning {
                            let confirmedText = self.confirmedSegments.map(\.text).joined(separator: " ")
                            self.webServer.broadcast(
                                confirmedText: confirmedText,
                                hypothesis: self.currentHypothesis,
                                audioLevel: self.audioLevel
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Web Server

    func startWebServer() {
        webServer.hyperDeckClient = hyperDeckClient
        webServer.start(port: webServerPort)
        isWebServerEnabled = true
        saveSettings()
    }

    func stopWebServer() {
        webServer.stop()
        isWebServerEnabled = false
        saveSettings()
    }

    // MARK: - HyperDeck

    func connectHyperDeck() {
        guard !hyperDeckHost.isEmpty else { return }
        hyperDeckClient.connect(host: hyperDeckHost, port: hyperDeckPort)
        isHyperDeckEnabled = true
        saveSettings()
    }

    func disconnectHyperDeck() {
        hyperDeckClient.disconnect()
        isHyperDeckEnabled = false
        saveSettings()
    }

    func stopListening() {
        hypothesisPollTask?.cancel()
        hypothesisPollTask = nil
        transcriptionService?.stopListening()
        isListening = false
        currentHypothesis = ""
        // Restart level monitoring now that WhisperKit's audio engine is stopped
        audioDeviceManager.startLevelMonitoring()
    }

    func resetWhisper() {
        stopListening()
        transcriptionService = nil
        confirmedSegments.removeAll()
        detectedVerses.removeAll()
        isModelLoaded = false
        isModelLoading = false
        modelDownloadProgress = 0.0
    }

    // MARK: - ProPresenter Connection

    func connectToProPresenter() async {
        proPresenterAPI.host = proPresenterHost
        proPresenterAPI.port = proPresenterPort
        let connected = await proPresenterAPI.checkConnection()
        await MainActor.run {
            self.isProPresenterConnected = connected
        }
        if !connected {
            showError("Could not connect to ProPresenter at \(proPresenterHost):\(proPresenterPort). Check that Pro7 is running and the network API is enabled.")
        }
        saveSettings()
        startAutoReconnect()
    }

    private func startAutoReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard let self, !Task.isCancelled else { return }
                let connected = await self.proPresenterAPI.checkConnection()
                await MainActor.run {
                    self.isProPresenterConnected = connected
                }
            }
        }
    }

    func indexBibleLibrary() async {
        proPresenterAPI.host = proPresenterHost
        proPresenterAPI.port = proPresenterPort

        if presentationIndexer == nil {
            presentationIndexer = PresentationIndexer(api: proPresenterAPI)
        }
        await presentationIndexer!.indexBiblePresentations(libraryName: bibleLibraryName)

        if let error = presentationIndexer?.errorMessage {
            showError(error)
        }
    }

    // MARK: - Verse Capture Pipeline

    func captureVerseSlide(_ verse: DetectedVerse) async {
        // Check confidence threshold
        let confidenceValue: Double
        switch verse.confidence {
        case .high: confidenceValue = 1.0
        case .medium: confidenceValue = 0.7
        case .low: confidenceValue = 0.4
        }
        guard confidenceValue >= confidenceThreshold else { return }

        guard let indexer = presentationIndexer else { return }

        // Expand range into individual verse references
        let verseStart = verse.reference.verseStart
        let verseEnd = verse.reference.verseEnd ?? verseStart
        var versesToCapture: [BibleReference] = []
        for v in verseStart...verseEnd {
            let singleRef = BibleReference(
                bookCode: verse.reference.bookCode,
                bookName: verse.reference.bookName,
                chapter: verse.reference.chapter,
                verseStart: v,
                verseEnd: nil
            )
            let key = singleRef.displayString
            let alreadyCaptured = capturedVerseKeys.contains(key)
            logger.debug("captureVerseSlide: Checking '\(key)' - alreadyCaptured: \(alreadyCaptured)")
            if !alreadyCaptured {
                // Insert immediately to prevent race condition with concurrent detections
                capturedVerseKeys.insert(key)
                versesToCapture.append(singleRef)
            }
        }

        // All verses in this detection already captured → mark as duplicate
        if versesToCapture.isEmpty {
            logger.info("captureVerseSlide: Marking as DUPLICATE - all verses already captured")
            await MainActor.run {
                if let idx = self.detectedVerses.firstIndex(where: { $0.id == verse.id }) {
                    self.detectedVerses[idx].status = .duplicate
                }
            }
            return
        }

        // Verify at least one verse can be found in Pro7
        let firstLookup = versesToCapture.first.flatMap { indexer.map.lookup($0) }
        if firstLookup == nil {
            if let firstRef = versesToCapture.first {
                logger.error("captureVerseSlide: LOOKUP FAILED for \(firstRef.displayString)")
                logger.error("  - map.hasBook('\(firstRef.bookCode)'): \(indexer.map.hasBook(firstRef.bookCode))")
                logger.error("  - map.count: \(indexer.map.count)")
            }
            await MainActor.run {
                if let idx = self.detectedVerses.firstIndex(where: { $0.id == verse.id }) {
                    self.detectedVerses[idx].status = .failed(error: "Verse not found in ProPresenter library")
                }
            }
            return
        }

        await MainActor.run {
            if let idx = self.detectedVerses.firstIndex(where: { $0.id == verse.id }) {
                self.detectedVerses[idx].status = .capturing
            }
        }

        var lastFilename = ""
        var capturedCount = 0

        for ref in versesToCapture {
            guard let location = indexer.map.lookup(ref) else { continue }

            // Fetch image data once from ProPresenter
            let imageData: Data
            do {
                imageData = try await SlideImageCapture.fetchSlideImage(
                    api: proPresenterAPI,
                    presentationUUID: location.presentationUUID,
                    slideIndex: location.slideIndex
                )
            } catch {
                await MainActor.run {
                    if let idx = self.detectedVerses.firstIndex(where: { $0.id == verse.id }) {
                        self.detectedVerses[idx].status = .failed(error: error.localizedDescription)
                    }
                }
                return
            }

            // Write to ALL available output folders
            var firstFileURL: URL?
            for folderURL in outputFolderURLs {
                guard outputFolderAvailability[folderURL] == true else {
                    logger.warning("Skipping unavailable folder: \(folderURL.path)")
                    continue
                }

                let seqNum = nextSequenceNumbers[folderURL, default: 1]
                let filename = String(format: "%03d_%@.png", seqNum, ref.filenameString)
                let fileURL = folderURL.appendingPathComponent(filename)

                do {
                    try imageData.write(to: fileURL)
                    await MainActor.run {
                        self.nextSequenceNumbers[folderURL] = seqNum + 1
                    }
                    lastFilename = filename
                    if firstFileURL == nil { firstFileURL = fileURL }
                    logger.info("Saved \(filename) to \(folderURL.lastPathComponent)")
                } catch {
                    logger.error("Failed to write to \(folderURL.path): \(error.localizedDescription)")
                }
            }

            capturedCount += 1

            await MainActor.run {
                logger.info("captureVerseSlide: CAPTURED '\(ref.displayString)'")
                // Note: capturedVerseKeys already updated before capture started (race condition fix)
                if let fileURL = firstFileURL {
                    self.capturedImages.append(CapturedVerse(
                        reference: ref.displayString,
                        filename: lastFilename,
                        imageURL: fileURL,
                        timestamp: Date()
                    ))
                }
            }
        }

        await MainActor.run {
            if let idx = self.detectedVerses.firstIndex(where: { $0.id == verse.id }) {
                if capturedCount > 1 {
                    self.detectedVerses[idx].status = .saved(filename: "\(capturedCount) slides")
                } else {
                    self.detectedVerses[idx].status = .saved(filename: lastFilename)
                }
            }
        }
    }
}

struct CapturedVerse: Identifiable {
    let id = UUID()
    let reference: String
    let filename: String
    let imageURL: URL
    let timestamp: Date

    enum Status {
        case saving
        case saved
        case failed(String)
    }
    var status: Status = .saved
}
