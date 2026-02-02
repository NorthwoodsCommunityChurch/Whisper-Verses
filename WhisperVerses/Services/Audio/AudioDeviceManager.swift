import Foundation
import CoreAudio
import AVFoundation

@Observable
final class AudioDeviceManager {
    var devices: [AudioDevice] = []
    var selectedDeviceID: AudioDeviceID?
    var currentLevel: Float = 0.0

    private var audioEngine: AVAudioEngine?
    private var levelTimer: Timer?

    init() {
        refreshDevices()
    }

    func refreshDevices() {
        devices = Self.enumerateInputDevices()
    }

    /// Set the system default input to the selected device, then start monitoring levels.
    func selectDevice(_ device: AudioDevice) {
        selectedDeviceID = device.id
        setSystemDefaultInput(device.id)
        startLevelMonitoring()
    }

    func startLevelMonitoring() {
        stopLevelMonitoring()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frames {
                sum += channelData[i] * channelData[i]
            }
            let rms = sqrt(sum / Float(frames))
            DispatchQueue.main.async {
                self?.currentLevel = rms
            }
        }

        do {
            try engine.start()
            audioEngine = engine
        } catch {
            print("AudioDeviceManager: Failed to start engine: \(error)")
        }
    }

    func stopLevelMonitoring() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        currentLevel = 0
    }

    // MARK: - CoreAudio Device Enumeration

    private static func enumerateInputDevices() -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )
        guard status == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return [] }

        return deviceIDs.compactMap { deviceID -> AudioDevice? in
            let name = getDeviceName(deviceID)
            let inputChannels = getInputChannelCount(deviceID)
            guard inputChannels > 0 else { return nil }
            return AudioDevice(id: deviceID, name: name, inputChannelCount: inputChannels)
        }
    }

    private static func getDeviceName(_ deviceID: AudioDeviceID) -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0, nil,
            &dataSize,
            &name
        )

        return status == noErr ? name as String : "Unknown Device"
    }

    private static func getInputChannelCount(_ deviceID: AudioDeviceID) -> Int {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return 0 }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(dataSize) / MemoryLayout<AudioBufferList>.stride + 1)
        defer { bufferListPointer.deallocate() }

        status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, bufferListPointer)
        guard status == noErr else { return 0 }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        var channelCount = 0
        for buffer in bufferList {
            channelCount += Int(buffer.mNumberChannels)
        }
        return channelCount
    }

    private func setSystemDefaultInput(_ deviceID: AudioDeviceID) {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var mutableDeviceID = deviceID
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &mutableDeviceID
        )
    }
}
