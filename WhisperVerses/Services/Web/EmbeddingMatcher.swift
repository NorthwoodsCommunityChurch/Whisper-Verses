import Foundation
import MLX
import MLXEmbedders
import OSLog

private let logger = Logger(subsystem: "com.northwoods.WhisperVerses", category: "EmbeddingMatcher")

final class EmbeddingMatcher {
    private var modelContainer: MLXEmbedders.ModelContainer?

    // Chunk embeddings (built when manuscript loaded)
    private var chunkEmbeddings: [[Float]] = []

    // Tracking state
    private(set) var currentChunkIndex: Int = 0
    private(set) var matchConfidence: Double = 0.0
    private(set) var isOffScript: Bool = false

    // Smoothing: require consistent readings before moving
    private var positionHistory: [Int] = []
    private let smoothingCount = 3

    // Similarity thresholds
    private let offScriptThreshold: Double = 0.25

    /// Whether the model is loaded and ready for inference
    var isModelLoaded: Bool { modelContainer != nil }

    /// Whether chunk embeddings have been built for a manuscript
    var isIndexBuilt: Bool { !chunkEmbeddings.isEmpty }

    // MARK: - Model Loading

    func loadModel(progressHandler: @Sendable @escaping (Progress) -> Void = { _ in }) async throws {
        let configuration = MLXEmbedders.ModelConfiguration.minilm_l6
        logger.info("Loading embedding model: \(configuration.name)")
        modelContainer = try await MLXEmbedders.loadModelContainer(
            configuration: configuration,
            progressHandler: progressHandler
        )
        logger.info("Embedding model loaded successfully")
    }

    // MARK: - Index Building

    func buildIndex(from chunkTexts: [String]) async {
        chunkEmbeddings = []
        currentChunkIndex = 0
        positionHistory = []
        matchConfidence = 0.0
        isOffScript = false

        guard let container = modelContainer, !chunkTexts.isEmpty else {
            logger.warning("Cannot build index: model not loaded or no chunks")
            return
        }

        let startTime = Date()

        for (i, text) in chunkTexts.enumerated() {
            let embedding = await embed(text: text, container: container)
            chunkEmbeddings.append(embedding)
            if (i + 1) % 10 == 0 || i == chunkTexts.count - 1 {
                logger.info("Embedded \(i + 1)/\(chunkTexts.count) chunks")
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)
        logger.info("Built embedding index: \(chunkTexts.count) chunks in \(String(format: "%.1f", elapsed))s")
    }

    // MARK: - Position Finding

    func findPosition(transcript: String) async {
        guard let container = modelContainer, !chunkEmbeddings.isEmpty else { return }

        // Use last ~100 words of transcript for matching
        let words = transcript.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let recentText = words.suffix(100).joined(separator: " ")
        guard !recentText.isEmpty else { return }

        let transcriptEmbedding = await embed(text: recentText, container: container)

        // Find best matching chunk by cosine similarity
        var bestIndex = 0
        var bestSimilarity: Double = -1.0

        for (i, chunkEmb) in chunkEmbeddings.enumerated() {
            let sim = cosineSimilarity(transcriptEmbedding, chunkEmb)
            if sim > bestSimilarity {
                bestSimilarity = sim
                bestIndex = i
            }
        }

        // Smoothing — require consistent readings before changing position
        positionHistory.append(bestIndex)
        if positionHistory.count > smoothingCount {
            positionHistory.removeFirst()
        }

        if bestSimilarity >= offScriptThreshold {
            let targetCount = positionHistory.filter { $0 == bestIndex }.count

            // Going backward needs full agreement, forward needs 2/3 majority
            let needed = bestIndex < currentChunkIndex
                ? smoothingCount
                : max(2, smoothingCount * 2 / 3)

            if targetCount >= needed && bestIndex != currentChunkIndex {
                logger.info("CHUNK: \(self.currentChunkIndex) → \(bestIndex) (sim \(String(format: "%.3f", bestSimilarity)))")
                currentChunkIndex = bestIndex
            }
        }

        matchConfidence = max(0, bestSimilarity)
        isOffScript = bestSimilarity < offScriptThreshold
    }

    func reset() {
        chunkEmbeddings = []
        currentChunkIndex = 0
        positionHistory = []
        matchConfidence = 0.0
        isOffScript = false
    }

    // MARK: - Private

    private func embed(text: String, container: MLXEmbedders.ModelContainer) async -> [Float] {
        await container.perform { model, tokenizer, pooler in
            let tokens = tokenizer.encode(text: text)
            let input = MLXArray(tokens).expandedDimensions(axis: 0)
            let output = model(input, positionIds: nil, tokenTypeIds: nil, attentionMask: nil)
            let pooled = pooler(output, normalize: true)
            eval(pooled)
            return pooled.squeezed().asArray(Float.self)
        }
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        // Embeddings are L2-normalized, so cosine similarity = dot product
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
        }
        return Double(dot)
    }
}
