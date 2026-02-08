import AVFoundation
import WhisperKit
import os

/// Thread-safe subclass of WhisperKit's AudioProcessor.
///
/// WhisperKit's AudioProcessor has a data race: the audio tap callback writes to
/// `audioSamples` and `audioEnergy` on the RealtimeMessenger dispatch queue, while
/// the transcription loop reads them on a separate async task. This causes crashes
/// when array growth/reallocation races with concurrent reads (use-after-free).
///
/// This subclass overrides the mutable properties with locked accessors. Each
/// individual property access is atomic, preventing the buffer corruption.
/// The tradeoff is COW copy overhead on each mutating access (append triggers
/// get → copy → mutate → set), but this is acceptable for audio buffer sizes.
final class ThreadSafeAudioProcessor: AudioProcessor {
    private let _lock = NSRecursiveLock()

    /// Input gain multiplier (0.5 to 3.0). Set from AppState.
    /// Using nonisolated(unsafe) since this is accessed from audio callback thread.
    nonisolated(unsafe) static var inputGain: Float = 1.0

    /// Current RMS audio level for UI display.
    /// Updated on each audioSamples write so the meter can show activity during transcription.
    nonisolated(unsafe) static var currentRMSLevel: Float = 0.0

    /// Tracks how many samples have already had gain applied to avoid re-amplifying.
    private var _gainAppliedCount: Int = 0

    /// Debug: track last log time to avoid spam
    private var _lastLogTime: Date = .distantPast

    override var audioSamples: ContiguousArray<Float> {
        get {
            _lock.lock()
            defer { _lock.unlock() }
            return super.audioSamples
        }
        set {
            _lock.lock()
            defer { _lock.unlock() }

            let gain = Self.inputGain

            // If array was cleared or shrunk, reset our tracking
            if newValue.count < _gainAppliedCount {
                _gainAppliedCount = 0
            }

            // Apply gain only to newly added samples (avoid re-amplifying)
            if gain != 1.0 && newValue.count > _gainAppliedCount {
                var modified = newValue
                for i in _gainAppliedCount..<modified.count {
                    modified[i] *= gain
                }
                _gainAppliedCount = modified.count
                super.audioSamples = modified
            } else {
                _gainAppliedCount = newValue.count
                super.audioSamples = newValue
            }

            // Compute RMS for UI level meter from gain-applied samples
            let samples = super.audioSamples
            let sampleCount = samples.count
            if sampleCount > 0 {
                // Use last ~50ms of audio at 16kHz = 800 samples for responsive meter
                let recentCount = min(800, sampleCount)
                let startIdx = sampleCount - recentCount
                var sum: Float = 0
                for i in startIdx..<sampleCount {
                    let sample = samples[i]
                    sum += sample * sample
                }
                Self.currentRMSLevel = sqrt(sum / Float(recentCount))
            } else {
                Self.currentRMSLevel = 0
            }

            // Debug logging (every 2 seconds) - write to file for remote debugging
            let now = Date()
            if now.timeIntervalSince(_lastLogTime) >= 2.0 {
                _lastLogTime = now
                let msg = "[AudioProcessor] samples=\(sampleCount), rms=\(String(format: "%.4f", Self.currentRMSLevel)), gain=\(gain)\n"
                Self.appendToDebugLog(msg)
            }
        }
    }

    override var audioEnergy: [(rel: Float, avg: Float, max: Float, min: Float)] {
        get {
            _lock.lock()
            defer { _lock.unlock() }
            return super.audioEnergy
        }
        set {
            _lock.lock()
            defer { _lock.unlock() }
            super.audioEnergy = newValue
        }
    }

    override var relativeEnergy: [Float] {
        _lock.lock()
        defer { _lock.unlock() }
        return super.relativeEnergy
    }

    /// Write debug message to /tmp/whisper_debug.log for remote troubleshooting
    static func appendToDebugLog(_ message: String) {
        let url = URL(fileURLWithPath: "/tmp/whisper_debug.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: url)
            }
        }
    }
}
