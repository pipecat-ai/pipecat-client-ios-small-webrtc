import Foundation
import PipecatClientIOS

extension [ServiceConfig] {
    var serverUrl: String? {
        let apiKeyOption = serviceConfig?.options.first { $0.name == "server_url" }
        if case let .string(apiKey) = apiKeyOption?.value {
            return apiKey
        }
        return nil
    }
    
    var serviceConfig: ServiceConfig? {
        first { $0.service == SmallWebRTCTransport.SERVICE_NAME }
    }
}

extension Value {
    var asObject: [String: Value] {
        if case .object(let dict) = self {
            return dict
        }
        return [:]
    }
    
    var asString: String {
        if case .object(_) = self {
            do {
                let jsonData = try JSONEncoder().encode(self)
                return String(data: jsonData, encoding: .utf8)!
            } catch {}
        } else if case .string(let stringValue) = self {
            return stringValue
        }
        return ""
    }
}
