import Foundation
import PipecatClientIOS

public struct SmallWebRTCTransportConnectionParams: TransportConnectionParams {

    let webrtcRequestParams: APIRequest

    enum CodingKeys: CodingKey {
        case webrtcRequestParams
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.webrtcRequestParams = try container.decode(APIRequest.self, forKey: .webrtcRequestParams)
    }

    public init(webrtcRequestParams: APIRequest) {
        self.webrtcRequestParams = webrtcRequestParams
    }

}
