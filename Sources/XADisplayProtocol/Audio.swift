import Foundation

public enum AudioRouteMode: String, Codable, Equatable {
    /// Every app except this host (`excludesCurrentProcessAudio`).
    case all
    /// Only the bundle ids the user checked.
    case selected
    /// Apps that currently have a window on the virtual display.
    case displayApps
}

public enum AudioFilterChoice: Equatable {
    /// No include-list. The display filter still excludes this process.
    case allApplications
    case includingBundles([String])
}

public enum AudioRoutePlanner {
    public static func choice(mode: AudioRouteMode, selectedBundleIDs: [String], bundlesOnDisplay: [String]) -> AudioFilterChoice {
        switch mode {
        case .all:
            return .allApplications
        case .selected:
            return .includingBundles(uniqueSorted(selectedBundleIDs))
        case .displayApps:
            return .includingBundles(uniqueSorted(bundlesOnDisplay))
        }
    }

    public static func bundleIDsOnDisplay(windows: [(pid: Int, bounds: XARect)], display: XARect, bundlesByPID: [Int: String]) -> [String] {
        var ids: [String] = []
        for window in windows where window.bounds.intersects(display) {
            if let bundle = bundlesByPID[window.pid], !bundle.isEmpty, !ids.contains(bundle) {
                ids.append(bundle)
            }
        }
        return ids.sorted()
    }

    private static func uniqueSorted(_ ids: [String]) -> [String] {
        Array(Set(ids.filter { !$0.isEmpty })).sorted()
    }
}

public enum AudioSyncMath {
    /// Hold about three AAC packets (1024 samples at 48 kHz is ~21 ms).
    public static let targetJitterMs = 60.0
    public static let maxLateMs = 140.0
    public static let maxQueuedPackets = 6

    /// Client clock minus host clock, using the midpoint of a ping.
    /// Returns nil when the sample is nonsense.
    public static func clockOffsetClientMinusHost(clientSendMs: Double, hostMs: Double, clientRecvMs: Double) -> Double? {
        guard clientSendMs.isFinite, hostMs.isFinite, clientRecvMs.isFinite, clientRecvMs >= clientSendMs else { return nil }
        let rtt = clientRecvMs - clientSendMs
        guard rtt < 10_000 else { return nil }
        let midpoint = clientSendMs + rtt / 2
        return midpoint - hostMs
    }

    /// When the iPad should start this packet, on the iPad clock.
    public static func scheduledPlayMs(hostCaptureMs: Double, offsetClientMinusHost: Double, jitterMs: Double = targetJitterMs) -> Double {
        hostCaptureMs + offsetClientMinusHost + jitterMs
    }

    public enum Decision: Equatable {
        case play
        case hold
        case dropLate
        case dropOverflow
    }

    public static func schedule(nowClientMs: Double, scheduledMs: Double, queued: Int) -> Decision {
        if queued > maxQueuedPackets { return .dropOverflow }
        if nowClientMs + 0.5 < scheduledMs { return .hold }
        if nowClientMs - scheduledMs > maxLateMs { return .dropLate }
        return .play
    }
}

public struct AudioPacketSlot: Equatable {
    public var hostMs: Double
    public var payload: Data
    public init(hostMs: Double, payload: Data) {
        self.hostMs = hostMs
        self.payload = payload
    }
}

/// Bounded jitter queue. Late packets are dropped. Overflow drops the oldest.
public struct AudioJitterQueue: Equatable {
    public private(set) var slots: [AudioPacketSlot] = []
    public var offsetClientMinusHost: Double = 0

    public init() {}

    public mutating func push(hostMs: Double, payload: Data) -> AudioSyncMath.Decision {
        if slots.count >= AudioSyncMath.maxQueuedPackets {
            slots.removeFirst()
            slots.append(AudioPacketSlot(hostMs: hostMs, payload: payload))
            slots.sort { $0.hostMs < $1.hostMs }
            return .dropOverflow
        }
        slots.append(AudioPacketSlot(hostMs: hostMs, payload: payload))
        slots.sort { $0.hostMs < $1.hostMs }
        return .hold
    }

    public mutating func popReady(nowClientMs: Double) -> AudioPacketSlot? {
        guard let first = slots.first else { return nil }
        let scheduled = AudioSyncMath.scheduledPlayMs(hostCaptureMs: first.hostMs, offsetClientMinusHost: offsetClientMinusHost)
        switch AudioSyncMath.schedule(nowClientMs: nowClientMs, scheduledMs: scheduled, queued: slots.count) {
        case .play:
            return slots.removeFirst()
        case .dropLate:
            slots.removeFirst()
            return popReady(nowClientMs: nowClientMs)
        case .hold, .dropOverflow:
            return nil
        }
    }
}

public enum AACPacket {
    /// AAC-LC payload: u16 cookie length, cookie, then one access unit. Both pieces stay inside the 8 KB audio cap.
    public static func pack(cookie: Data, frame: Data) -> Data? {
        guard cookie.count <= 512, frame.count > 0, 2 + cookie.count + frame.count <= XAAudio.maxBytes else { return nil }
        var data = Data()
        data.append(UInt8(cookie.count >> 8))
        data.append(UInt8(cookie.count & 0xff))
        data.append(cookie)
        data.append(frame)
        return data
    }

    public static func unpack(_ payload: Data) -> (cookie: Data, frame: Data)? {
        guard payload.count >= 3 else { return nil }
        let cookieCount = (Int(payload[0]) << 8) | Int(payload[1])
        guard cookieCount <= 512, payload.count >= 2 + cookieCount + 1 else { return nil }
        let cookie = payload.subdata(in: 2..<(2 + cookieCount))
        let frame = payload.subdata(in: (2 + cookieCount)..<payload.count)
        return (cookie, frame)
    }
}

public enum AudioVolume {
    /// Little-endian signed 16-bit samples, the layout XA sends for PCM.
    public static func scalePCM16(pcm: Data, volume: Double) -> Data {
        let gain = min(1, max(0, volume))
        var output = Data()
        let count = pcm.count - (pcm.count % 2)
        output.reserveCapacity(count)
        var offset = 0
        while offset + 1 < count {
            let bits = UInt16(pcm[offset]) | (UInt16(pcm[offset + 1]) << 8)
            let sample = Int16(bitPattern: bits)
            let scaled = Double(sample) * gain
            let clamped = min(Double(Int16.max), max(Double(Int16.min), scaled.rounded()))
            let stored = UInt16(bitPattern: Int16(clamped))
            output.append(UInt8(stored & 0xff))
            output.append(UInt8(stored >> 8))
            offset += 2
        }
        return output
    }
}
