import Foundation

/// Typed failures for the Mac host. Recovery text is safe to show in the menu.
enum HostError: Error, Equatable {
    case transport(String)
    case pairing
    case permission(String)
    case codec(String)
    case virtualDisplay

    var userMessage: String {
        switch self {
        case .transport(let detail): return "Link failed. \(detail)"
        case .pairing: return "The iPad pairing proof was rejected."
        case .permission(let kind): return "\(kind) permission is missing."
        case .codec(let detail): return "The encoder rejected the frame. \(detail)"
        case .virtualDisplay: return "The virtual display could not be created."
        }
    }
}
