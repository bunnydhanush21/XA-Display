import Foundation

public enum ConnectionFailure: Equatable {
    case transport
    case pairing
    case permission
    case timedOut
}

public enum ConnectionPhase: Equatable {
    case idle
    case discovering
    case connecting
    case pairing
    case streaming
    case reconnecting
    case failed(ConnectionFailure)
}

public enum ConnectionEvent: Equatable {
    case startDiscovery
    case beginConnect
    case transportReady
    case helloAccepted
    case authAccepted
    case authRejected
    case linkLost
    case userStop
    case retry
}

public enum ConnectionMachine {
    public static func reduce(_ phase: ConnectionPhase, _ event: ConnectionEvent) -> ConnectionPhase {
        switch event {
        case .userStop:
            return .idle
        case .retry:
            return .discovering
        case .startDiscovery:
            return phase == .streaming ? .streaming : .discovering
        case .beginConnect:
            return .connecting
        case .transportReady:
            return .pairing
        case .helloAccepted:
            return phase == .streaming ? .streaming : .pairing
        case .authAccepted:
            return .streaming
        case .authRejected:
            return .failed(.pairing)
        case .linkLost:
            switch phase {
            case .streaming, .pairing, .reconnecting:
                return .reconnecting
            case .connecting, .discovering:
                return .failed(.transport)
            case .idle, .failed:
                return phase
            }
        }
    }
}

public enum MenuBadge: Equatable {
    public static func name(for phase: ConnectionPhase) -> String {
        switch phase {
        case .streaming: return "green"
        case .connecting, .discovering, .pairing, .reconnecting: return "yellow"
        case .failed: return "red"
        case .idle: return "gray"
        }
    }
}

public struct MenuSnapshot: Equatable {
    public var phase: ConnectionPhase
    public var peerName: String
    public var transport: String
    public var latency: String
    public var fps: String
    public var preset: String
    public var audio: Bool
    public var clipboard: Bool
    public var touch: Bool
    public var lowLatency: Bool
    public var screenRecording: Bool
    public var accessibility: Bool

    public init(
        phase: ConnectionPhase, peerName: String, transport: String, latency: String, fps: String, preset: String,
        audio: Bool, clipboard: Bool, touch: Bool, lowLatency: Bool, screenRecording: Bool, accessibility: Bool
    ) {
        self.phase = phase
        self.peerName = peerName
        self.transport = transport
        self.latency = latency
        self.fps = fps
        self.preset = preset
        self.audio = audio
        self.clipboard = clipboard
        self.touch = touch
        self.lowLatency = lowLatency
        self.screenRecording = screenRecording
        self.accessibility = accessibility
    }
}
