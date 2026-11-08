import Foundation

/// Typed failures for the iPad app. Shown in the connection screen or a toast.
enum PadError: Error, Equatable {
    case transport(String)
    case pairing
    case decode
    case protocolVersion

    var userMessage: String {
        switch self {
        case .transport(let detail): return "Not connected. \(detail)"
        case .pairing: return "Enter the pairing code from the Mac."
        case .decode: return "The picture could not be decoded. The Mac should drop to Safe."
        case .protocolVersion: return "This iPad build does not match the Mac host."
        }
    }
}
