import CoreAudio
import Foundation
import SwiftUI

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
    var outputFolderURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        .appendingPathComponent("ProPresenter/WhisperVerses", isDirectory: true)
    var capturedImages: [CapturedVerse] = []
    var nextSequenceNumber: Int = 1

    // MARK: - Live Slide Preview
    var liveSlideImageData: Data?
    var liveSlidePresentationName: String = ""
    var liveSlideVerseLabel: String = ""
    var liveSlideText: String = ""
    var liveSlideIndex: Int = 0

    // MARK: - Settings
    var confidenceThreshold: Double = 0.7
    var hasCompletedOnboarding: Bool = false

    // MARK: - Error Display
    var errorMessage: String?
    @ObservationIgnored private var errorDismissTask: Task<Void, Never>?

    // MARK: - Services
    var audioDeviceManager = AudioDeviceManager()
    var transcriptionService: TranscriptionService?
    var verseDetector = VerseDetector()
    var proPresenterAPI = ProPresenterAPI()
    var presentationIndexer: PresentationIndexer?
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var slidePollingTask: Task<Void, Never>?
    @ObservationIgnored private var lastSlideFingerprint: String = ""
    @ObservationIgnored private var hypothesisPollTask: Task<Void, Never>?

    init() {
        loadSettings()
        ensureOutputFolder()
    }

    private func ensureOutputFolder() {
        try? FileManager.default.createDirectory(at: outputFolderURL, withIntermediateDirectories: true)
    }

    func clearOutputFolder() {
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: outputFolderURL, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "png" {
                try? fm.removeItem(at: file)
            }
        }
        capturedImages.removeAll()
        nextSequenceNumber = 1
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
        if let path = defaults.string(forKey: "outputFolderPath") {
            outputFolderURL = URL(fileURLWithPath: path)
        }
        let threshold = defaults.double(forKey: "confidenceThreshold")
        if threshold > 0 { confidenceThreshold = threshold }
        let deviceID = defaults.integer(forKey: "selectedAudioDeviceID")
        if deviceID > 0 { selectedAudioDeviceID = AudioDeviceID(deviceID) }
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
    }

    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(proPresenterHost, forKey: "proPresenterHost")
        defaults.set(proPresenterPort, forKey: "proPresenterPort")
        defaults.set(bibleLibraryName, forKey: "bibleLibraryName")
        defaults.set(outputFolderURL.path, forKey: "outputFolderPath")
        defaults.set(confidenceThreshold, forKey: "confidenceThreshold")
        if let deviceID = selectedAudioDeviceID {
            defaults.set(Int(deviceID), forKey: "selectedAudioDeviceID")
        }
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

                let detected = detector.detect(in: segment.text)
                let enrichedSegment = TranscriptSegment(
                    text: segment.text,
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    isConfirmed: segment.isConfirmed,
                    detectedReferences: detected.map { $0.reference }
                )
                self.confirmedSegments.append(enrichedSegment)

                for verse in detected {
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

        await service.startListening()
        isListening = service.isListening

        if let error = service.errorMessage {
            showError(error)
        }

        // Poll hypothesis text for live partial results
        if isListening {
            hypothesisPollTask?.cancel()
            hypothesisPollTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
                    guard let self, !Task.isCancelled else { return }
                    await MainActor.run {
                        self.currentHypothesis = service.currentText
                    }
                }
            }
        }
    }

    func stopListening() {
        hypothesisPollTask?.cancel()
        hypothesisPollTask = nil
        transcriptionService?.stopListening()
        isListening = false
        currentHypothesis = ""
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
        } else {
            startSlidePolling()
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
                let wasConnected = self.isProPresenterConnected
                await MainActor.run {
                    self.isProPresenterConnected = connected
                }
                // Start polling if we just reconnected
                if connected && !wasConnected {
                    self.startSlidePolling()
                }
            }
        }
    }

    // MARK: - Live Slide Polling

    private func startSlidePolling() {
        slidePollingTask?.cancel()
        slidePollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, !Task.isCancelled else { return }
                await self.pollCurrentSlide()
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            }
        }
    }

    private func pollCurrentSlide() async {
        // Fetch both endpoints concurrently
        async let slideResult = proPresenterAPI.getSlideStatus()
        async let indexResult = proPresenterAPI.getSlideIndex()

        guard let status = await slideResult else { return }
        let indexStatus = await indexResult

        // Build fingerprint from slide UUID to detect changes
        let fingerprint = status.currentUUID.isEmpty ? status.currentText : status.currentUUID
        guard !fingerprint.isEmpty, fingerprint != lastSlideFingerprint else { return }
        lastSlideFingerprint = fingerprint

        // Update state
        let presName = indexStatus?.presentationName ?? ""
        let slideIndex = indexStatus?.slideIndex ?? 0
        let presUUID = indexStatus?.presentationUUID ?? ""

        // Compute verse label from slide index if we have the index built
        let verseLabel = presentationIndexer?.map.verseLabel(
            presentationUUID: presUUID,
            slideIndex: slideIndex
        ) ?? presName

        await MainActor.run {
            self.liveSlidePresentationName = presName
            self.liveSlideVerseLabel = verseLabel
            self.liveSlideText = status.currentText
            self.liveSlideIndex = slideIndex
        }

        // Fetch thumbnail for the new slide
        if !presUUID.isEmpty {
            do {
                let imageData = try await proPresenterAPI.getSlideImage(
                    presentationUUID: presUUID,
                    slideIndex: slideIndex,
                    quality: 400
                )
                await MainActor.run {
                    self.liveSlideImageData = imageData
                }
            } catch {
                // Thumbnail fetch failed — keep showing previous
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
        guard let location = indexer.map.lookup(verse.reference) else {
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

        let seqNum = nextSequenceNumber
        await MainActor.run { self.nextSequenceNumber += 1 }

        do {
            let (fileURL, filename) = try await SlideImageCapture.captureAndSave(
                api: proPresenterAPI,
                presentationUUID: location.presentationUUID,
                slideIndex: location.slideIndex,
                reference: verse.reference,
                sequenceNumber: seqNum,
                outputFolder: outputFolderURL
            )

            await MainActor.run {
                if let idx = self.detectedVerses.firstIndex(where: { $0.id == verse.id }) {
                    self.detectedVerses[idx].status = .saved(filename: filename)
                }
                self.capturedImages.append(CapturedVerse(
                    reference: verse.reference.displayString,
                    filename: filename,
                    imageURL: fileURL,
                    timestamp: Date()
                ))
            }
        } catch {
            await MainActor.run {
                if let idx = self.detectedVerses.firstIndex(where: { $0.id == verse.id }) {
                    self.detectedVerses[idx].status = .failed(error: error.localizedDescription)
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
