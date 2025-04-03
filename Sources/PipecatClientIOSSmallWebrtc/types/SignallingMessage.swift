import Foundation

// Constant for signalling type
public let SIGNALLING_TYPE = "signalling"

// Enum for signalling messages
public enum SignallingMessage: String, Codable {
    case renegotiate = "renegotiate"
}
