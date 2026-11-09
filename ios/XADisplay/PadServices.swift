import Foundation
import XADisplayProtocol

/// Session.
protocol PadSessionDriving: AnyObject {
    var phase: ConnectionPhase { get set }
    func apply(_ event: ConnectionEvent)
}

final class PadSession: PadSessionDriving {
    var phase = ConnectionPhase.idle
    func apply(_ event: ConnectionEvent) {
        phase = ConnectionMachine.reduce(phase, event)
    }
}

/// Permissions.
struct PadPermissions: Equatable {
    var localNetwork: Bool
}

/// Connection.
struct PadConnectionService {
    func overlayVisible(connected: Bool) -> Bool { !connected }

    func phase(connected: Bool, paused: Bool) -> ConnectionEvent {
        if paused { return .userStop }
        return connected ? .authAccepted : .beginConnect
    }
}

/// Display.
struct PadDisplayService {
    func rotation(mode: String, portrait: Bool, follow: Bool, lock: String, letterbox: Bool) -> Bool {
        let wantPortrait = OrientationPolicy.resolved(device: portrait ? "portrait" : "landscape", follow: follow, lock: lock) == "portrait"
        return !letterbox && mode == "stream" && wantPortrait && portrait
    }
}

/// Input.
struct PadInputService {
    func normalized(point: XAPoint, view: XASize, video: XASize, rotation: XARotation, pixelsPerPoint: Double) -> XAPoint? {
        CoordinateMapper.normalize(MapRequest(point: point, pointSpace: .viewPoints, viewSizePoints: view, pixelsPerPoint: pixelsPerPoint, videoPixelSize: video, rotation: rotation))
    }
}

/// Audio.
struct PadAudioService {
    func accepts(enabled: Bool, armed: Bool, byteCount: Int, channels: Int) -> Bool {
        AudioPolicy.accept(enabled: enabled, armed: armed, byteCount: byteCount, channels: channels)
    }
}

/// Clipboard.
struct PadClipboardService {
    func accepts(enabled: Bool, armed: Bool, text: String) -> Bool {
        ClipboardPolicy.accept(enabled: enabled, armed: armed, utf8Count: text.utf8.count)
    }
}
