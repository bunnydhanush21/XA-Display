import Foundation

public enum XAChannel: String, Equatable {
    case video, audio, clipboard, input
}

public enum ChannelAuth {
    public static func proof(token: String, channel: XAChannel, nonce: String) -> String {
        let key = HMACSHA256.digest(key: Array("xa-display-session-v1".utf8), message: Array(PairingGate.normalize(token).utf8))
        let message = Array("\(channel.rawValue)\n\(nonce)".utf8)
        return HMACSHA256.digest(key: key, message: message).map { String(format: "%02x", $0) }.joined()
    }

    public static func verify(token: String, channel: XAChannel, nonce: String, proof: String) -> Bool {
        let expected = Array(self.proof(token: token, channel: channel, nonce: nonce).utf8)
        let presented = Array(proof.lowercased().utf8)
        var diff = expected.count ^ presented.count
        let count = max(expected.count, presented.count)
        if count == 0 { return false }
        for index in 0..<count {
            let left = index < expected.count ? expected[index] : 0
            let right = index < presented.count ? presented[index] : 0
            diff |= Int(left ^ right)
        }
        return diff == 0 && !PairingGate.normalize(token).isEmpty
    }
}

public struct ChannelGate: Equatable {
    public var requireAuth: Bool
    public private(set) var video = false
    public private(set) var input = false

    public init(requireAuth: Bool) { self.requireAuth = requireAuth }

    public mutating func acceptVideo(token: String, nonce: String, proof: String) -> Bool {
        guard ChannelAuth.verify(token: token, channel: .video, nonce: nonce, proof: proof) else {
            video = false
            return false
        }
        video = true
        return true
    }

    public mutating func noteInputArmed(_ armed: Bool) { input = armed }

    public mutating func reset() {
        video = false
        input = false
    }

    public func allows(_ channel: XAChannel) -> Bool {
        if !requireAuth { return true }
        switch channel {
        case .video: return video
        case .input, .audio, .clipboard: return input
        }
    }
}

public enum XAError: Equatable, Error {
    public enum Permission: String, Equatable {
        case screenRecording, accessibility, localNetwork
    }

    case transport(String)
    case pairing(String)
    case permission(Permission)
    case codec(String)
    case protocolVersion(expected: Int, got: Int)

    public var userMessage: String {
        switch self {
        case .transport(let detail): return "The link failed. \(detail)"
        case .pairing: return "The pairing code was not accepted."
        case .permission(let kind): return "\(kind.rawValue) permission is missing."
        case .codec(let detail): return "Video could not be decoded. \(detail)"
        case .protocolVersion(let expected, let got): return "This build speaks protocol \(expected). The other side sent \(got)."
        }
    }

    public var recovery: String {
        switch self {
        case .transport: return "Plug in the cable or join the same Wi-Fi, then connect again."
        case .pairing: return "Enter the pairing code shown on the Mac."
        case .permission(let kind):
            switch kind {
            case .screenRecording: return "Open System Settings and allow Screen Recording, then quit and reopen the host."
            case .accessibility: return "Open System Settings and allow Accessibility."
            case .localNetwork: return "Allow local network access for XA Display on the iPad."
            }
        case .codec: return "Switch the display preset to Safe."
        case .protocolVersion: return "Update both the Mac and the iPad apps together."
        }
    }
}
