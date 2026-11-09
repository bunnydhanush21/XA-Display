import Foundation

/// StreamPreset.
public struct StreamPreset: Equatable, Codable, Sendable {
    /// ID.
    public enum ID: String, Equatable, Codable, Sendable {
        case balanced, safe, native
    }

    public var id: ID
    public var width: Int
    public var height: Int
    public var fps: Int
    public var profile: String
    public var level: String
    public var bitrateUSB: Int
    public var bitrateWiFi: Int
    public var allowBFrames: Bool
    public var experimental: Bool

    public init(id: ID, width: Int, height: Int, fps: Int, profile: String, level: String, bitrateUSB: Int, bitrateWiFi: Int, allowBFrames: Bool, experimental: Bool) {
        self.id = id
        self.width = width
        self.height = height
        self.fps = fps
        self.profile = profile
        self.level = level
        self.bitrateUSB = bitrateUSB
        self.bitrateWiFi = bitrateWiFi
        self.allowBFrames = allowBFrames
        self.experimental = experimental
    }

    public static let balanced = StreamPreset(
        id: .balanced, width: 1440, height: 1080, fps: 30,
        profile: "main", level: "4.1",
        bitrateUSB: 8_000_000, bitrateWiFi: 6_000_000,
        allowBFrames: false, experimental: false
    )
    public static let safe = StreamPreset(
        id: .safe, width: 1024, height: 768, fps: 30,
        profile: "main", level: "3.1",
        bitrateUSB: 4_000_000, bitrateWiFi: 3_000_000,
        allowBFrames: false, experimental: false
    )
    /// 2048×1536 and 1536×2048 are 12,288 macroblocks. At 60 fps that is Level 5.1. OpenDisplay has decoded this mode on an iPad mini 3; XA has not measured it yet, so it stays experimental and is not the USB default.
    public static let native = StreamPreset(
        id: .native, width: 2048, height: 1536, fps: 60,
        profile: "main", level: "5.1",
        bitrateUSB: 18_000_000, bitrateWiFi: 12_000_000,
        allowBFrames: false, experimental: true
    )

    public static func preset(_ id: ID) -> StreamPreset {
        switch id {
        case .balanced: return .balanced
        case .safe: return .safe
        case .native: return .native
        }
    }

    public func oriented(portrait: Bool) -> StreamPreset {
        var copy = self
        if portrait == (width > height) {
            swap(&copy.width, &copy.height)
        }
        return copy
    }

    public func bitrate(usb: Bool) -> Int { usb ? bitrateUSB : bitrateWiFi }

    public var macroblocksPerFrame: Int {
        ((width + 15) / 16) * ((height + 15) / 16)
    }

    public var macroblocksPerSecond: Int { macroblocksPerFrame * fps }

    /// VideoToolbox profile-level name, for example `H264_Main_4_1`.
    public var profileLevelName: String {
        let profileName: String
        switch profile {
        case "baseline": profileName = "Baseline"
        case "high": profileName = "High"
        default: profileName = "Main"
        }
        let levelName = level.replacingOccurrences(of: ".", with: "_")
        return "H264_\(profileName)_\(levelName)"
    }
}

/// PresetFallback.
public enum PresetFallback {
    public static func afterDecodeFailure(_ id: StreamPreset.ID) -> StreamPreset.ID? {
        switch id {
        case .native: return .balanced
        case .balanced: return .safe
        case .safe: return nil
        }
    }
}

/// AdaptationSignals.
public struct AdaptationSignals: Equatable {
    public var thermal: ThermalBucket
    public var batteryFraction: Double?
    public var onExternalPower: Bool
    public var inputRTTMs: Double?
    public var pipelineMs: Double?
    public var sendBacklogFrames: Int
    public var decodeFailed: Bool
    public var batteryHeat: Bool

    public init(
        thermal: ThermalBucket = .nominal, batteryFraction: Double? = 1, onExternalPower: Bool = true, inputRTTMs: Double? = 10, pipelineMs: Double? = 20, sendBacklogFrames: Int = 0,
        decodeFailed: Bool = false, batteryHeat: Bool = false
    ) {
        self.thermal = thermal
        self.batteryFraction = batteryFraction
        self.onExternalPower = onExternalPower
        self.inputRTTMs = inputRTTMs
        self.pipelineMs = pipelineMs
        self.sendBacklogFrames = sendBacklogFrames
        self.decodeFailed = decodeFailed
        self.batteryHeat = batteryHeat
    }
}

/// StreamTune.
public struct StreamTune: Equatable {
    public var preset: StreamPreset.ID
    public var fps: Int
    public var bitrate: Int
    public var reason: String
    public init(preset: StreamPreset.ID, fps: Int, bitrate: Int, reason: String) {
        self.preset = preset
        self.fps = fps
        self.bitrate = bitrate
        self.reason = reason
    }
}

/// AdaptationController.
public struct AdaptationController {
    public private(set) var preset: StreamPreset.ID
    public private(set) var fps: Int
    public private(set) var bitrate: Int
    public var usb: Bool
    public private(set) var secondsSinceChange: Double
    public private(set) var healthySeconds: Double
    public let minimumBitrate = 2_000_000

    public init(preset: StreamPreset.ID, usb: Bool) {
        self.preset = preset
        self.usb = usb
        let spec = StreamPreset.preset(preset)
        self.fps = spec.fps
        self.bitrate = spec.bitrate(usb: usb)
        self.secondsSinceChange = 100
        self.healthySeconds = 0
    }

    public mutating func applyOverride(fps: Int, bitrate: Int) {
        self.fps = min(60, max(10, fps))
        self.bitrate = min(20_000_000, max(minimumBitrate, bitrate))
    }

    public mutating func advance(dt: Double, signals: AdaptationSignals) -> StreamTune? {
        let step = max(0, dt)
        secondsSinceChange += step
        if signals.thermal == .critical {
            healthySeconds = 0
            let safeRate = min(2_500_000, StreamPreset.safe.bitrate(usb: usb))
            return apply(preset: .safe, fps: 15, bitrate: safeRate, reason: "thermal critical")
        }
        if signals.decodeFailed {
            healthySeconds = 0
            if let next = PresetFallback.afterDecodeFailure(preset) {
                let spec = StreamPreset.preset(next)
                return apply(preset: next, fps: spec.fps, bitrate: spec.bitrate(usb: usb), reason: "decode failure")
            }
            return apply(preset: preset, fps: min(fps, 15), bitrate: max(minimumBitrate, bitrate / 2), reason: "decode failure at safe")
        }
        if secondsSinceChange < 2 { return nil }

        if signals.thermal == .serious {
            healthySeconds = 0
            let stepped = PresetFallback.afterDecodeFailure(preset) ?? preset
            let spec = StreamPreset.preset(stepped)
            return apply(preset: stepped, fps: min(15, spec.fps), bitrate: max(minimumBitrate, spec.bitrate(usb: usb) / 2), reason: "thermal serious")
        }

        let congested = (signals.pipelineMs ?? 0) > 120 || (signals.inputRTTMs ?? 0) > 80 || signals.sendBacklogFrames >= 2
        let lowBattery = (signals.batteryFraction ?? 1) < 0.15 && !signals.onExternalPower
        if congested || signals.thermal == .fair || lowBattery || signals.batteryHeat {
            healthySeconds = 0
            var reason = "congestion"
            if signals.thermal == .fair { reason = "thermal fair" }
            if lowBattery { reason = "low battery" }
            if signals.batteryHeat { reason = "battery temperature" }
            let reduced = max(minimumBitrate, bitrate * 7 / 10)
            if reduced < bitrate {
                return apply(preset: preset, fps: fps, bitrate: reduced, reason: reason)
            }
            if fps > 15 {
                return apply(preset: preset, fps: max(15, fps - 6), bitrate: bitrate, reason: reason)
            }
            return nil
        }

        if signals.thermal == .nominal {
            healthySeconds += step
        } else {
            healthySeconds = 0
        }
        let target = StreamPreset.preset(preset)
        let targetRate = target.bitrate(usb: usb)
        if healthySeconds >= 20 && (bitrate < targetRate || fps < target.fps) {
            let raised = min(targetRate, Int(Double(bitrate) * 1.15) + 1_000)
            let raisedFPS = min(target.fps, fps < target.fps ? fps + 5 : fps)
            return apply(preset: preset, fps: raisedFPS, bitrate: raised, reason: "recover")
        }
        return nil
    }

    private mutating func apply(preset: StreamPreset.ID, fps: Int, bitrate: Int, reason: String) -> StreamTune? {
        if self.preset == preset && self.fps == fps && self.bitrate == bitrate { return nil }
        self.preset = preset
        self.fps = fps
        self.bitrate = bitrate
        secondsSinceChange = 0
        return StreamTune(preset: preset, fps: fps, bitrate: bitrate, reason: reason)
    }
}

/// FrameDecision.
public enum FrameDecision: Equatable {
    case show
    case dropUntilKeyframe
    case dropStale
    case dropOverflow
}

/// FrameAdmission.
public struct FrameAdmission: Equatable {
    public var awaitingKeyframe: Bool
    public var maxQueued: Int
    public init(awaitingKeyframe: Bool = false, maxQueued: Int = 1) {
        self.awaitingKeyframe = awaitingKeyframe
        self.maxQueued = maxQueued
    }

    public mutating func decide(isKeyframe: Bool, queued: Int, ageMs: Double, maxAgeMs: Double = 150) -> FrameDecision {
        if awaitingKeyframe && !isKeyframe { return .dropUntilKeyframe }
        if !isKeyframe && ageMs > maxAgeMs {
            awaitingKeyframe = true
            return .dropStale
        }
        if !isKeyframe && queued >= maxQueued {
            awaitingKeyframe = true
            return .dropOverflow
        }
        if isKeyframe { awaitingKeyframe = false }
        return .show
    }
}

/// InFlightGate.
public struct InFlightGate: Equatable {
    public var inFlight: Bool
    public var needsKeyframe: Bool
    /// Permit.
    public enum Permit: Equatable {
        case encode(forceKeyframe: Bool)
        case drop
    }
    public init(inFlight: Bool = false, needsKeyframe: Bool = true) {
        self.inFlight = inFlight
        self.needsKeyframe = needsKeyframe
    }
    public mutating func begin() -> Permit {
        if inFlight {
            needsKeyframe = true
            return .drop
        }
        let force = needsKeyframe
        needsKeyframe = false
        inFlight = true
        return .encode(forceKeyframe: force)
    }
    public mutating func finished() { inFlight = false }
}

/// SendBudget.
public struct SendBudget: Equatable {
    public var maxPending: Int
    public var needsKeyframe: Bool
    /// Decision.
    public enum Decision: Equatable { case send, drop }
    public init(maxPending: Int = 2, needsKeyframe: Bool = true) {
        self.maxPending = maxPending
        self.needsKeyframe = needsKeyframe
    }
    public mutating func admit(pending: Int, isKeyframe: Bool) -> Decision {
        if pending >= maxPending {
            needsKeyframe = true
            return .drop
        }
        if needsKeyframe && !isKeyframe { return .drop }
        if isKeyframe { needsKeyframe = false }
        return .send
    }
}

/// TransportKind.
public enum TransportKind: String, Equatable, Codable {
    case usb, wifi, none
}

/// LinkPreference.
public enum LinkPreference {
    public static func desired(usbAvailable: Bool, wifiAvailable: Bool, wifiAllowed: Bool) -> TransportKind {
        if usbAvailable { return .usb }
        if wifiAllowed && wifiAvailable { return .wifi }
        return .none
    }
    public static func shouldSwitch(current: TransportKind, desired: TransportKind) -> Bool {
        desired != .none && desired != current
    }
}

/// TransportHeuristic.
public enum TransportHeuristic {
    public static func classify(remoteHost: String) -> TransportKind {
        let host = remoteHost.lowercased()
        if host == "127.0.0.1" || host == "::1" || host == "localhost" || host == "::ffff:127.0.0.1" {
            return .usb
        }
        if host.isEmpty { return .none }
        return .wifi
    }
}

/// UsbmuxPort.
public enum UsbmuxPort {
    /// Apple's usbmuxd plist `PortNumber` is the TCP port in network byte order, zero-extended.
    public static func networkOrder(_ port: UInt16) -> UInt32 {
        UInt32(port.byteSwapped)
    }
    public static func candidates(_ port: UInt16) -> [UInt32] {
        let swapped = networkOrder(port)
        let plain = UInt32(port)
        if swapped == plain { return [plain] }
        return [swapped, plain]
    }
}

/// LatencyMath.
public enum LatencyMath {
    /// Host-clock interval from capture to the echoed ack. Includes the return trip. Not glass-to-glass.
    public static func captureToAck(captureMs: Double, ackMs: Double) -> Double? {
        guard captureMs.isFinite, ackMs.isFinite, ackMs >= captureMs, ackMs - captureMs < 10_000 else { return nil }
        return ackMs - captureMs
    }
    /// Client-clock interval from receiving an access unit until it is handed to the hardware decoder.
    public static func handoff(receiveMs: Double, enqueueMs: Double) -> Double? {
        guard receiveMs.isFinite, enqueueMs.isFinite, enqueueMs >= receiveMs, enqueueMs - receiveMs < 5_000 else { return nil }
        return enqueueMs - receiveMs
    }
}
