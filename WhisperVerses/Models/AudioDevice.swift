import Foundation
import CoreAudio

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let inputChannelCount: Int

    var isInput: Bool { inputChannelCount > 0 }
}
