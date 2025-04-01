import Foundation
import PipecatClientIOS

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
