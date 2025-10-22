import Foundation
import WebRTC

/// This enum is a swift wrapper over `RTCSdpType` for easy encode and decode
enum SdpType: String, Codable {
    case offer, prAnswer, answer, rollback

    var rtcSdpType: RTCSdpType {
        switch self {
        case .offer: return .offer
        case .answer: return .answer
        case .prAnswer: return .prAnswer
        case .rollback: return .rollback
        }
    }
}

/// This struct is a swift wrapper over `RTCSessionDescription` for easy encode and decode
struct SmallWebRTCSessionDescription: Codable {

    var sdp: String
    var pc_id: String?
    let type: SdpType
    // We are not handling this case in the iOS SDK yet.
    var restart_pc: Bool = false

    init(from rtcSessionDescription: RTCSessionDescription) {
        self.sdp = rtcSessionDescription.sdp

        switch rtcSessionDescription.type {
        case .offer: self.type = .offer
        case .prAnswer: self.type = .prAnswer
        case .answer: self.type = .answer
        case .rollback: self.type = .rollback
        @unknown default:
            fatalError("Unknown RTCSessionDescription type: \(rtcSessionDescription.type.rawValue)")
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sdp = try container.decode(String.self, forKey: .sdp)
        self.pc_id = try container.decodeIfPresent(String.self, forKey: .pc_id)
        self.type = try container.decode(SdpType.self, forKey: .type)
        self.restart_pc = try container.decodeIfPresent(Bool.self, forKey: .restart_pc) ?? false
    }

    var rtcSessionDescription: RTCSessionDescription {
        return RTCSessionDescription(type: self.type.rtcSdpType, sdp: self.sdp)
    }
}
