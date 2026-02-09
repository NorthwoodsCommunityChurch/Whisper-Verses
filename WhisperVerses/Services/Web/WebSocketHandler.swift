import Foundation
import CommonCrypto

enum WebSocketMessage {
    case text(String)
    case binary(Data)
    case close
}

enum WebSocketHandler {
    private static let webSocketGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    static func generateAcceptKey(from key: String?) -> String? {
        guard let key = key else { return nil }

        let combined = key + webSocketGUID
        guard let data = combined.data(using: .utf8) else { return nil }

        var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_SHA1(bytes.baseAddress, CC_LONG(data.count), &hash)
        }

        return Data(hash).base64EncodedString()
    }

    static func parseFrame(_ data: Data) -> WebSocketMessage? {
        guard data.count >= 2 else { return nil }

        let byte0 = data[0]
        let byte1 = data[1]

        let opcode = byte0 & 0x0F
        let isMasked = (byte1 & 0x80) != 0
        var payloadLength = UInt64(byte1 & 0x7F)

        var offset = 2

        if payloadLength == 126 {
            guard data.count >= 4 else { return nil }
            payloadLength = UInt64(data[2]) << 8 | UInt64(data[3])
            offset = 4
        } else if payloadLength == 127 {
            guard data.count >= 10 else { return nil }
            payloadLength = 0
            for i in 0..<8 {
                payloadLength = payloadLength << 8 | UInt64(data[2 + i])
            }
            offset = 10
        }

        var maskKey: [UInt8] = []
        if isMasked {
            guard data.count >= offset + 4 else { return nil }
            maskKey = Array(data[offset..<offset + 4])
            offset += 4
        }

        guard data.count >= offset + Int(payloadLength) else { return nil }

        var payload = Array(data[offset..<offset + Int(payloadLength)])

        // Unmask if necessary
        if isMasked {
            for i in 0..<payload.count {
                payload[i] ^= maskKey[i % 4]
            }
        }

        switch opcode {
        case 0x01: // Text frame
            if let text = String(bytes: payload, encoding: .utf8) {
                return .text(text)
            }
        case 0x02: // Binary frame
            return .binary(Data(payload))
        case 0x08: // Close frame
            return .close
        default:
            break
        }

        return nil
    }

    static func createTextFrame(_ data: Data) -> Data {
        var frame = Data()

        // FIN bit + text opcode (0x81)
        frame.append(0x81)

        // Payload length (server frames are not masked)
        if data.count < 126 {
            frame.append(UInt8(data.count))
        } else if data.count < 65536 {
            frame.append(126)
            frame.append(UInt8((data.count >> 8) & 0xFF))
            frame.append(UInt8(data.count & 0xFF))
        } else {
            frame.append(127)
            for i in (0..<8).reversed() {
                frame.append(UInt8((data.count >> (i * 8)) & 0xFF))
            }
        }

        frame.append(data)
        return frame
    }

    static func createCloseFrame() -> Data {
        var frame = Data()
        frame.append(0x88) // FIN + close opcode
        frame.append(0x00) // No payload
        return frame
    }
}
