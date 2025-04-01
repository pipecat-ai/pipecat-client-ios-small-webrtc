import Foundation
import PipecatClientIOS

extension [ServiceConfig] {
    var initialMessages: [OpenAIMessages.Outbound.Conversation] {
        let initialMessagesKeyOption = llmConfig?.options.first { $0.name == "initial_messages" }
        return initialMessagesKeyOption?.value.toConversationArray() ?? []
    }
    
    var llmConfig: ServiceConfig? {
        first { $0.service == "llm" }
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
        if case .object(let dict) = self {
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
