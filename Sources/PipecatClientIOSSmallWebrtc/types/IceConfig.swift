import Foundation

// MARK: - Public API
import WebRTC

public struct IceConfig: Codable {
    public let iceServers: [IceServer]

    public init(iceServers: [IceServer]) {
        self.iceServers = iceServers
    }
}

public struct IceServer: Codable {
    public let urls: [String]
    public let username: String?
    public let credential: String?

    public init(urls: [String], username: String? = nil, credential: String? = nil) {
        self.urls = urls
        self.username = username
        self.credential = credential
    }
}

// MARK: - Extension to convert to WebRTC
extension IceServer {
    var rtcIceServer: RTCIceServer {
        RTCIceServer(
            urlStrings: urls,
            username: username,
            credential: credential
        )
    }
}

extension IceConfig {
    var rtcIceServers: [RTCIceServer] {
        iceServers.map { $0.rtcIceServer }
    }
}
