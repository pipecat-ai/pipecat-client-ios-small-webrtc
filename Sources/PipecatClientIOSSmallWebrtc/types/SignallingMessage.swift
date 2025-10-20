import Foundation

// MARK: - Base Protocols

public let SIGNALLING_TYPE = "signalling"

/// Common protocol for all signalling messages
protocol SignallingMessageProtocol: Codable {
    var type: String { get }
}

/// Marker protocol for inbound messages (received from remote peer/server)
protocol InboundSignallingMessageProtocol: SignallingMessageProtocol {}

/// Marker protocol for outbound messages (sent to remote peer/server)
protocol OutboundSignallingMessageProtocol: SignallingMessageProtocol {}

// MARK: - Outbound Messages

struct TrackStatusMessage: OutboundSignallingMessageProtocol {
    let type = "trackStatus"
    let receiverIndex: Int
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case type
        case receiverIndex = "receiver_index"
        case enabled
    }
}

/// Wraps any signalling message (inbound or outbound)
struct OutboundSignallingMessage: Encodable {
    let type = "signalling"
    let message: SignallingMessageProtocol

    enum CodingKeys: String, CodingKey {
        case type
        case message
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)

        // Encode based on concrete type
        switch message {
        case let trackStatus as TrackStatusMessage:
            try container.encode(trackStatus, forKey: .message)
        default:
            let context = EncodingError.Context(
                codingPath: encoder.codingPath,
                debugDescription: "Unsupported signalling message type: \(Swift.type(of: message))"
            )
            throw EncodingError.invalidValue(message, context)
        }
    }
}

// MARK: - Inbound Messages

struct RenegotiateMessage: InboundSignallingMessageProtocol {
    let type = "renegotiate"
}

struct PeerLeftMessage: InboundSignallingMessageProtocol {
    let type = "peerLeft"
}

enum InboundSignallingMessage: Decodable {
    case renegotiate(RenegotiateMessage)
    case peerLeft(PeerLeftMessage)

    enum CodingKeys: String, CodingKey {
        case type
    }

    enum MessageType: String {
        case renegotiate
        case peerLeft
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)

        guard let type = MessageType(rawValue: typeString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown inbound message type: \(typeString)"
            )
        }

        switch type {
        case .renegotiate:
            let message = try RenegotiateMessage(from: decoder)
            self = .renegotiate(message)
        case .peerLeft:
            let message = try PeerLeftMessage(from: decoder)
            self = .peerLeft(message)
        }
    }
}
