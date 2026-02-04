import Foundation
import WhisperKit

@Observable
final class TranscriptionService {
    var isListening = false
    var currentText: String = ""
    var confirmedSegments: [TranscriptSegment] = []
    var isModelLoaded = false
    var modelDownloadProgress: Double = 0.0
    var errorMessage: String?

    private var whisperKit: WhisperKit?
    private var streamTranscriber: AudioStreamTranscriber?
    private var transcriptionTask: Task<Void, Never>?
    private var lastConfirmedCount = 0

    /// Called when a new confirmed segment is available
    var onSegmentConfirmed: ((TranscriptSegment) -> Void)?

    var isModelLoading = false

    func loadModel() async {
        do {
            await MainActor.run {
                isModelLoaded = false
                isModelLoading = true
                errorMessage = nil
                modelDownloadProgress = 0.0
            }

            // Download model with progress tracking
            let modelURL = try await WhisperKit.download(
                variant: "large-v3_turbo",
                from: "argmaxinc/whisperkit-coreml",
                progressCallback: { [weak self] progress in
                    Task { @MainActor in
                        self?.modelDownloadProgress = progress.fractionCompleted
                    }
                }
            )

            await MainActor.run {
                modelDownloadProgress = 1.0
            }

            // Initialize with downloaded model (no re-download)
            // Use ThreadSafeAudioProcessor to prevent data race crash in WhisperKit's
            // AudioProcessor (audio tap callback writes vs transcription loop reads)
            let config = WhisperKitConfig(
                modelFolder: modelURL.path,
                computeOptions: ModelComputeOptions(
                    audioEncoderCompute: .cpuAndNeuralEngine,
                    textDecoderCompute: .cpuAndNeuralEngine
                ),
                audioProcessor: ThreadSafeAudioProcessor(),
                verbose: false,
                load: true,
                download: false
            )

            whisperKit = try await WhisperKit(config)
            await MainActor.run {
                isModelLoaded = true
                isModelLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load model: \(error.localizedDescription)"
                isModelLoading = false
            }
            print("TranscriptionService: Model load error: \(error)")
        }
    }

    func startListening() async {
        guard let whisperKit, isModelLoaded else {
            errorMessage = "Model not loaded"
            return
        }

        guard let tokenizer = whisperKit.tokenizer else {
            errorMessage = "Tokenizer not available"
            return
        }

        await MainActor.run {
            isListening = true
            currentText = ""
            lastConfirmedCount = 0
            errorMessage = nil
        }

        let decodingOptions = DecodingOptions(
            language: "en",
            temperature: 0.0,
            wordTimestamps: true
        )

        let streamer = AudioStreamTranscriber(
            audioEncoder: whisperKit.audioEncoder,
            featureExtractor: whisperKit.featureExtractor,
            segmentSeeker: whisperKit.segmentSeeker,
            textDecoder: whisperKit.textDecoder,
            tokenizer: tokenizer,
            audioProcessor: whisperKit.audioProcessor,
            decodingOptions: decodingOptions,
            requiredSegmentsForConfirmation: 1,
            silenceThreshold: 0.3,
            useVAD: true,
            stateChangeCallback: { [weak self] oldState, newState in
                Task { @MainActor in
                    self?.handleStateChange(oldState: oldState, newState: newState)
                }
            }
        )

        streamTranscriber = streamer

        transcriptionTask = Task {
            do {
                try await streamer.startStreamTranscription()
            } catch {
                if !Task.isCancelled {
                    await MainActor.run { [weak self] in
                        self?.errorMessage = "Transcription error: \(error.localizedDescription)"
                        self?.isListening = false
                    }
                }
            }
        }
    }

    func stopListening() {
        Task {
            await streamTranscriber?.stopStreamTranscription()
        }
        transcriptionTask?.cancel()
        transcriptionTask = nil
        streamTranscriber = nil
        isListening = false
        currentText = ""
    }

    @MainActor
    private func handleStateChange(
        oldState: AudioStreamTranscriber.State,
        newState: AudioStreamTranscriber.State
    ) {
        // Update hypothesis text from unconfirmed segments.
        // Only clear hypothesis when there's genuinely nothing pending.
        let unconfirmedText = newState.unconfirmedSegments.map(\.text).joined(separator: " ")
        let rawHypothesis = Self.stripTokens(
            (newState.currentText + " " + unconfirmedText)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if !rawHypothesis.isEmpty {
            currentText = rawHypothesis
        } else if newState.confirmedSegments.count > lastConfirmedCount {
            // New confirmation arrived — clear hypothesis since it moved to confirmed
            currentText = ""
        }
        // Otherwise keep the previous hypothesis to avoid flickering

        // Process newly confirmed segments.
        // Reset tracking if state was cleared (e.g., VAD silence break resets the array).
        let newConfirmed = newState.confirmedSegments
        if newConfirmed.count < lastConfirmedCount {
            lastConfirmedCount = 0
        }
        if newConfirmed.count > lastConfirmedCount {
            for i in lastConfirmedCount..<newConfirmed.count {
                let segment = newConfirmed[i]
                let text = Self.stripTokens(segment.text)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }

                let transcriptSegment = TranscriptSegment(
                    text: text,
                    startTime: TimeInterval(segment.start),
                    endTime: TimeInterval(segment.end),
                    isConfirmed: true
                )

                confirmedSegments.append(transcriptSegment)
                onSegmentConfirmed?(transcriptSegment)
            }
            lastConfirmedCount = newConfirmed.count
        }
    }

    /// Strip WhisperKit special tokens like <|startoftranscript|>, <|en|>, <|0.00|>, etc.
    private static func stripTokens(_ text: String) -> String {
        text.replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    func clearTranscript() {
        confirmedSegments.removeAll()
        currentText = ""
        lastConfirmedCount = 0
    }
}
