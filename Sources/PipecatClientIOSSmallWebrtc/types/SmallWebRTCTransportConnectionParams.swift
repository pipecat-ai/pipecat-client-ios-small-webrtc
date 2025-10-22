import Foundation
import PipecatClientIOS

public struct SmallWebRTCTransportConnectionParams: TransportConnectionParams, StartBotResult {

    let webrtcRequestParams: APIRequest
    let iceConfig: IceConfig?

    enum CodingKeys: CodingKey {
        case webrtcRequestParams
        case iceConfig
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.webrtcRequestParams = try container.decode(APIRequest.self, forKey: .webrtcRequestParams)
        self.iceConfig = try container.decodeIfPresent(IceConfig.self, forKey: .iceConfig)
    }

    public init(webrtcRequestParams: APIRequest, iceConfig: IceConfig? = nil) {
        self.webrtcRequestParams = webrtcRequestParams
        self.iceConfig = iceConfig
    }

}
