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
    var capturedVerseKeys: Set<String> = []  // Tracks individual verses already captured (e.g., "John 3:16")
    var nextSequenceNumber: Int = 1

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
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var hypothesisPollTask: Task<Void, Never>?

    init() {
        loadSettings()
        ensureOutputFolder()
        updateService.startPeriodicChecks()
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
        capturedVerseKeys.removeAll()
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
        let savedGain = defaults.float(forKey: "inputGain")
        if savedGain > 0 { inputGain = savedGain }
        // Sync to the static property used by audio processor
        ThreadSafeAudioProcessor.inputGain = inputGain
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
        defaults.set(inputGain, forKey: "inputGain")
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
            if !capturedVerseKeys.contains(key) {
                versesToCapture.append(singleRef)
            }
        }

        // All verses in this detection already captured → mark as duplicate
        if versesToCapture.isEmpty {
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

            let seqNum = nextSequenceNumber
            await MainActor.run { self.nextSequenceNumber += 1 }

            do {
                let (fileURL, filename) = try await SlideImageCapture.captureAndSave(
                    api: proPresenterAPI,
                    presentationUUID: location.presentationUUID,
                    slideIndex: location.slideIndex,
                    reference: ref,
                    sequenceNumber: seqNum,
                    outputFolder: outputFolderURL
                )

                lastFilename = filename
                capturedCount += 1

                await MainActor.run {
                    self.capturedVerseKeys.insert(ref.displayString)
                    self.capturedImages.append(CapturedVerse(
                        reference: ref.displayString,
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
                return
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
