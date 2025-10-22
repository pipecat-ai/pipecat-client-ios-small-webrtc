import Foundation
import PipecatClientIOS

public struct SmallWebRTCStartBotResult: StartBotResult {

    let sessionId: String
    let iceConfig: IceConfig?

    enum CodingKeys: CodingKey {
        case sessionId
        case iceConfig
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sessionId = try container.decode(String.self, forKey: .sessionId)
        self.iceConfig = try container.decodeIfPresent(IceConfig.self, forKey: .iceConfig)
    }

    public init(sessionId: String, iceConfig: IceConfig? = nil) {
        self.sessionId = sessionId
        self.iceConfig = iceConfig
    }

}
