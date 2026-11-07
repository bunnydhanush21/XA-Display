import Foundation

public enum MediaAction: UInt8, Equatable, Codable {
    case playPause = 1
    case next = 2
    case previous = 3
    case volumeUp = 4
    case volumeDown = 5
    case seekForward = 6
    case seekBackward = 7
}

/// NX media-key codes posted as system-defined events (subtype 8). Not private MediaRemote.
public enum MediaKeyMap {
    public static let systemDefinedSubtype: Int32 = 8
    public static let keyDownState: Int32 = 0xA
    public static let keyUpState: Int32 = 0xB

    public static func virtualKey(_ action: MediaAction) -> Int32 {
        switch action {
        case .volumeUp: return 0
        case .volumeDown: return 1
        case .playPause: return 16
        case .next: return 17
        case .previous: return 18
        case .seekForward: return 19
        case .seekBackward: return 20
        }
    }

    public static func data1(keyCode: Int32, down: Bool) -> Int32 {
        let state = down ? keyDownState : keyUpState
        return (keyCode << 16) | (state << 8)
    }
}

public struct XAMediaCommand: Equatable {
    public var session: UInt32
    public var seq: UInt32
    public var action: MediaAction
    /// Signed scrub amount in roughly -1...1. Zero means the action stands alone.
    public var scrub: Double

    public init(session: UInt32, seq: UInt32, action: MediaAction, scrub: Double = 0) {
        self.session = session
        self.seq = seq
        self.action = action
        self.scrub = scrub
    }
}

public struct XANowPlaying: Equatable {
    public static let unknownTime = -1.0
    public static let maxArtworkBytes = 65_536
    public var session: UInt32
    public var appName: String
    public var title: String
    public var artist: String
    public var position: Double
    public var duration: Double
    public var artworkPNG: Data

    public init(session: UInt32, appName: String, title: String = "", artist: String = "", position: Double = unknownTime, duration: Double = unknownTime, artworkPNG: Data = Data()) {
        self.session = session
        self.appName = appName
        self.title = title
        self.artist = artist
        self.position = position
        self.duration = duration
        self.artworkPNG = artworkPNG
    }

    public var hasPublicMetadata: Bool { !title.isEmpty || !artworkPNG.isEmpty }
}

public enum NowPlayingSource {
    /// No public API reads another app's now-playing item. The panel shows the frontmost app name.
    public static let usesPrivateMediaRemote = false
    public static let note = "Title, artist, artwork, and a real scrub bar need a public now-playing API. This build shows the frontmost app and sends media keys."
}
