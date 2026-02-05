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
    private var _lock = os_unfair_lock()

    /// Input gain multiplier (0.5 to 3.0). Set from AppState.
    /// Using nonisolated(unsafe) since this is accessed from audio callback thread.
    nonisolated(unsafe) static var inputGain: Float = 1.0

    /// Tracks how many samples have already had gain applied to avoid re-amplifying.
    private var _gainAppliedCount: Int = 0

    override var audioSamples: ContiguousArray<Float> {
        get {
            os_unfair_lock_lock(&_lock)
            defer { os_unfair_lock_unlock(&_lock) }
            return super.audioSamples
        }
        set {
            os_unfair_lock_lock(&_lock)
            defer { os_unfair_lock_unlock(&_lock) }

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
        }
    }

    override var audioEnergy: [(rel: Float, avg: Float, max: Float, min: Float)] {
        get {
            os_unfair_lock_lock(&_lock)
            defer { os_unfair_lock_unlock(&_lock) }
            return super.audioEnergy
        }
        set {
            os_unfair_lock_lock(&_lock)
            defer { os_unfair_lock_unlock(&_lock) }
            super.audioEnergy = newValue
        }
    }

    override var relativeEnergy: [Float] {
        os_unfair_lock_lock(&_lock)
        defer { os_unfair_lock_unlock(&_lock) }
        return super.relativeEnergy
    }
}
