import Foundation

public enum OrientationAction: Equatable {
    case ignore
    case reconfigure(width: Int, height: Int)
    case letterbox
    case rotateStream
}

public enum PortraitModes {
    /// Swapped preset size when it still fits the preset's H.264 level. Nil means letterbox.
    public static func size(preset: StreamPreset.ID) -> XASize? {
        let portrait = StreamPreset.preset(preset).oriented(portrait: true)
        guard H264LevelLimits.fits(width: portrait.width, height: portrait.height, level: portrait.level) else { return nil }
        return XASize(width: Double(portrait.width), height: Double(portrait.height))
    }

    public static func landscape(preset: StreamPreset.ID) -> XASize {
        let landscape = StreamPreset.preset(preset).oriented(portrait: false)
        return XASize(width: Double(landscape.width), height: Double(landscape.height))
    }
}

public enum OrientationPolicy {
    public static func resolved(device: String, follow: Bool, lock: String) -> String? {
        guard follow else { return nil }
        switch lock {
        case "portrait": return "portrait"
        case "landscape": return "landscape"
        default: return device == "portrait" ? "portrait" : "landscape"
        }
    }

    public static func action(currentPortrait: Bool, requested: String, follow: Bool, lock: String, mode: String, portraitSize: XASize?, landscapeSize: XASize) -> OrientationAction {
        guard let resolved = resolved(device: requested, follow: follow, lock: lock) else { return .ignore }
        let wantPortrait = resolved == "portrait"
        if mode == "stream" {
            return wantPortrait ? .rotateStream : .ignore
        }
        if wantPortrait == currentPortrait { return .ignore }
        if wantPortrait {
            guard let portraitSize else { return .letterbox }
            return .reconfigure(width: Int(portraitSize.width), height: Int(portraitSize.height))
        }
        return .reconfigure(width: Int(landscapeSize.width), height: Int(landscapeSize.height))
    }
}

public struct OrientationDebounce: Equatable {
    public static let seconds = 0.3
    public private(set) var latest: String?
    private var changedAt = -1.0
    private var emitted: String?

    public init() {}

    @discardableResult
    public mutating func note(_ orientation: String, now: Double) -> Bool {
        guard orientation != latest else { return false }
        latest = orientation
        changedAt = now
        return true
    }

    /// Marks an orientation as already sent, so the first hello does not also emit a live update.
    public mutating func adopt(_ orientation: String) {
        latest = orientation
        emitted = orientation
        changedAt = 0
    }

    public mutating func due(now: Double) -> String? {
        guard let latest, now - changedAt + 0.000_001 >= Self.seconds, latest != emitted else { return nil }
        emitted = latest
        return latest
    }
}

public enum OrientationMapping {
    /// Extra mapping when the Mac framebuffer stays landscape and the iPad view is portrait.
    public static func rotation(mode: String, devicePortrait: Bool) -> XARotation {
        if mode == "stream", devicePortrait { return .clockwise90 }
        return .identity
    }

    /// Turns a finger delta on a portrait view into framebuffer axes when the picture is rotated.
    public static func scrollDelta(_ delta: XAPoint, rotation: XARotation) -> XAPoint {
        switch rotation {
        case .identity:
            return delta
        case .clockwise90:
            return XAPoint(x: delta.y, y: -delta.x)
        case .clockwise180:
            return XAPoint(x: -delta.x, y: -delta.y)
        case .clockwise270:
            return XAPoint(x: -delta.y, y: delta.x)
        }
    }
}
