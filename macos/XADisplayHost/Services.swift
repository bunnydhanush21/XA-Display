@preconcurrency import ApplicationServices
@preconcurrency import Foundation
import XADisplayProtocol

/// Session.
protocol SessionDriving: Sendable {
    func send(_ event: ConnectionEvent) async -> ConnectionPhase
}

extension SessionCoordinator: SessionDriving {}

/// Permissions.
protocol PermissionChecking: Sendable {
    func snapshot() -> PermissionSnapshot
}

struct PermissionSnapshot: Equatable, Sendable {
    var screenRecording: Bool
    var accessibility: Bool
}

struct SystemPermissions: PermissionChecking {
    func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(screenRecording: CGPreflightScreenCaptureAccess(), accessibility: AXIsProcessTrusted())
    }
}

struct FixedPermissions: PermissionChecking {
    var screenRecording: Bool
    var accessibility: Bool
    func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(screenRecording: screenRecording, accessibility: accessibility)
    }
}

/// Display.
struct DisplayService: Sendable {
    func active(preset: StreamPreset, portrait: Bool, custom: CustomDisplaySettings) -> (width: Int, height: Int, scale: Double) {
        let base = custom.enabled ? custom.clamped().applying(to: StreamPreset.preset(preset.id)).oriented(portrait: portrait) : preset.oriented(portrait: portrait)
        let scale = preset.id == .native ? 2.0 : 1.0
        return (base.width, base.height, scale)
    }

    func plan(currentPortrait: Bool, requested: String, follow: Bool, lock: String, mode: String, preset: StreamPreset.ID) -> OrientationAction {
        OrientationPolicy.action(
            currentPortrait: currentPortrait,
            requested: requested,
            follow: follow,
            lock: lock,
            mode: mode,
            portraitSize: PortraitModes.size(preset: preset),
            landscapeSize: PortraitModes.landscape(preset: preset)
        )
    }
}

/// Connection.
struct ConnectionService: Sendable {
    func link(running: Bool, userPaused: Bool, autoUSB: Bool, transport: TransportKind, usb: Bool, wifiHost: String?, wifiAllowed: Bool) -> TransportKind? {
        guard running, !userPaused, autoUSB || transport != .none else { return nil }
        let desired = LinkPreference.desired(usbAvailable: usb, wifiAvailable: wifiHost != nil, wifiAllowed: wifiAllowed)
        if LinkPreference.shouldSwitch(current: transport, desired: desired) || (transport == .none && desired != .none) {
            return desired
        }
        return nil
    }
}

/// Clipboard.
struct ClipboardService: Sendable {
    func outbound(sync: Bool, armed: Bool, changeCount: Int, lastCount: Int, text: String?) -> String? {
        guard sync, armed, changeCount != lastCount, let text, !text.isEmpty, text.utf8.count <= XAClipboard.maxBytes else { return nil }
        return text
    }
}

/// Audio.
struct AudioService: Sendable {
    func shouldCapture(enabled: Bool, displayID: UInt32) -> Bool {
        enabled && displayID != 0
    }
}

/// Input.
struct InputService: Sendable {
    func allowsVideo(_ gate: ChannelGate) -> Bool { gate.allows(.video) }

    func failure(for message: VideoControlMessage, allowed: Bool) -> HostFailure? {
        switch message {
        case .xaAuth, .hello:
            return nil
        default:
            return allowed ? nil : .pairing
        }
    }
}

enum HostFailure: String, Error, Sendable {
    case transport
    case pairing
    case codec
    case virtualDisplay
    case permission

    var error: HostError {
        switch self {
        case .transport: return .transport("The video or input frame was rejected.")
        case .pairing: return .pairing
        case .codec: return .codec("Decode or capture failed.")
        case .virtualDisplay: return .virtualDisplay
        case .permission: return .permission("screen or accessibility")
        }
    }
}
