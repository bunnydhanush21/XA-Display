import Foundation

/// FrameLimits.
public struct FrameLimits: Equatable, Sendable {
    public var maxPayload: Int
    public var maxBuffer: Int
    public var partialTimeout: Double
    public var maxFramesPerAppend: Int

    public init(maxPayload: Int, maxBuffer: Int, partialTimeout: Double = 2, maxFramesPerAppend: Int = 64) {
        self.maxPayload = maxPayload
        self.maxBuffer = maxBuffer
        self.partialTimeout = partialTimeout
        self.maxFramesPerAppend = maxFramesPerAppend
    }

    /// Video access units. A 2048×1536 keyframe stays well under 2 MB; the buffer cannot grow past 3 MB.
    public static let video = FrameLimits(maxPayload: 2_000_000 + ChannelSeal.overhead, maxBuffer: 3_000_000)
    /// Input stays bounded. 256 KB covers one clipboard image and still rejects multi-megabyte frames.
    public static let input = FrameLimits(maxPayload: 262_144 + ChannelSeal.overhead, maxBuffer: 524_288, maxFramesPerAppend: 32)
}

/// FrameParseError.
public enum FrameParseError: Equatable, Error {
    case payloadTooLarge(declared: Int, max: Int)
    case bufferTooLarge(Int)
    case incompleteExpired
    case emptyPayload
}

/// FrameParseOutcome.
public enum FrameParseOutcome: Equatable {
    case ok([Data])
    case failed(FrameParseError)
}

/// Length-prefixed framing with hard caps.
///
/// The upstream iOS 12 receiver waited for whatever 32-bit length it was given and appended into an
/// unbounded `Data`. A hostile peer could advertise a multi-gigabyte frame. This parser rejects
/// oversized lengths before reading the body, caps the reassembly buffer, and expires incomplete frames.
public struct FrameParser {
    public let limits: FrameLimits
    public private(set) var buffer = Data()
    public private(set) var partialStartedAt: Double?
    public var bufferedByteCount: Int { buffer.count }

    public init(limits: FrameLimits) {
        self.limits = limits
    }

    public mutating func append(_ data: Data, now: Double) -> FrameParseOutcome {
        if data.isEmpty {
            return tick(now: now)
        }
        if data.count > limits.maxBuffer {
            buffer.removeAll(keepingCapacity: false)
            partialStartedAt = nil
            return .failed(.bufferTooLarge(data.count))
        }
        if buffer.count > limits.maxBuffer - data.count {
            let projected = buffer.count + data.count
            buffer.removeAll(keepingCapacity: false)
            partialStartedAt = nil
            return .failed(.bufferTooLarge(projected))
        }
        buffer.append(data)
        return drain(now: now)
    }

    public mutating func tick(now: Double) -> FrameParseOutcome {
        drain(now: now)
    }

    private mutating func drain(now: Double) -> FrameParseOutcome {
        var frames: [Data] = []
        while buffer.count >= 4 {
            if frames.count >= limits.maxFramesPerAppend {
                break
            }
            let declared = Int(Self.readU32BE(buffer, 0))
            if declared <= 0 {
                buffer.removeAll(keepingCapacity: false)
                partialStartedAt = nil
                return .failed(.emptyPayload)
            }
            if declared > limits.maxPayload {
                buffer.removeAll(keepingCapacity: false)
                partialStartedAt = nil
                return .failed(.payloadTooLarge(declared: declared, max: limits.maxPayload))
            }
            let total = 4 + declared
            if buffer.count < total {
                if partialStartedAt == nil {
                    partialStartedAt = now
                }
                if let started = partialStartedAt, now - started >= limits.partialTimeout {
                    buffer.removeAll(keepingCapacity: false)
                    partialStartedAt = nil
                    return .failed(.incompleteExpired)
                }
                break
            }
            partialStartedAt = nil
            let payload = buffer.subdata(in: 4..<total)
            buffer.removeSubrange(0..<total)
            frames.append(payload)
        }
        if buffer.count < 4 {
            partialStartedAt = nil
        }
        return .ok(frames)
    }

    public static func readU32BE(_ data: Data, _ offset: Int) -> UInt32 {
        (UInt32(data[offset]) << 24)
            | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8)
            | UInt32(data[offset + 3])
    }
}

/// LengthPrefixedFraming.
public enum LengthPrefixedFraming {
    public static func encode(_ payload: Data) -> Data {
        var header = UInt32(payload.count).bigEndian
        var out = Data(capacity: 4 + payload.count)
        withUnsafeBytes(of: &header) { out.append(contentsOf: $0) }
        out.append(payload)
        return out
    }
}

/// PayloadKind.
public enum PayloadKind: Equatable {
    case controlJSON
    case videoAccessUnit

    /// Same observable rule as the MIT receiver, plus an explicit size cap:
    /// a small `{` payload with no NUL byte is JSON; everything else is an access unit.
    public static func classify(_ data: Data, maxControlBytes: Int = 32_768) -> PayloadKind {
        guard data.count > 0, data.count <= maxControlBytes, data.first == UInt8(ascii: "{") else {
            return .videoAccessUnit
        }
        if data.contains(0) {
            return .videoAccessUnit
        }
        return .controlJSON
    }
}

/// NALUnit.
public struct NALUnit: Equatable {
    public var data: Data
    public init(data: Data) { self.data = data }
    public var type: Int {
        guard let first = data.first else { return -1 }
        return Int(first & 0x1F)
    }
}

/// TimingPrefix.
public struct TimingPrefix: Equatable {
    public var seq: UInt64
    public var captureMs: Double
    public var encodeMs: Double?
    public init(seq: UInt64, captureMs: Double, encodeMs: Double?) {
        self.seq = seq
        self.captureMs = captureMs
        self.encodeMs = encodeMs
    }
}

/// AnnexBAccessUnit.
public struct AnnexBAccessUnit: Equatable {
    public var timing: TimingPrefix?
    public var nalus: [NALUnit]
    public var truncated: Bool
    public init(timing: TimingPrefix?, nalus: [NALUnit], truncated: Bool) {
        self.timing = timing
        self.nalus = nalus
        self.truncated = truncated
    }

    public var isKeyframe: Bool {
        nalus.contains { $0.type == 5 }
    }
}

/// AnnexB.
public enum AnnexB {
    public static let maxNALUs = 64
    public static let maxTimingPrefix = 4_096

    public static func parse(_ payload: Data) -> AnnexBAccessUnit {
        let view = AnnexBSpan.scan(payload)
        var nalus: [NALUnit] = []
        nalus.reserveCapacity(view.spans.count)
        for span in view.spans {
            nalus.append(NALUnit(data: payload.subdata(in: span.range)))
        }
        return AnnexBAccessUnit(timing: view.timing, nalus: nalus, truncated: view.truncated)
    }

    public static func encode(timingJSON: Data?, nalus: [Data], prependParameterSets: [Data] = []) -> Data {
        var out = Data()
        if let timingJSON, !timingJSON.isEmpty {
            out.append(timingJSON)
        }
        let parts = prependParameterSets + nalus
        for nalu in parts {
            out.append(contentsOf: [0, 0, 0, 1])
            out.append(nalu)
        }
        return out
    }

    static func parseTiming(_ data: Data) -> TimingPrefix? {
        guard data.first == UInt8(ascii: "{"),
            let obj = JSON.object(data),
            JSON.string(obj["type"]) == "timing",
            let capture = JSON.double(obj["captureMs"])
        else { return nil }
        let seq = UInt64(JSON.int(obj["seq"]) ?? 0)
        return TimingPrefix(seq: seq, captureMs: capture, encodeMs: JSON.double(obj["encodeMs"]))
    }
}

enum JSON {
    static func object(_ data: Data) -> [String: Any]? {
        guard data.count <= 32_768, let parsed = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return dictionary(parsed)
    }

    static func dictionary(_ parsed: Any) -> [String: Any]? {
        if let dict = parsed as? [String: Any] { return dict }
        guard let dict = parsed as? NSDictionary else { return nil }
        var out: [String: Any] = [:]
        for (key, value) in dict {
            guard let key = key as? String else { continue }
            out[key] = value
        }
        return out
    }

    static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSString { return value as String }
        return nil
    }

    static func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double, value.isFinite { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }

    static func data(_ object: [String: Any]) -> Data? {
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object, options: [])
    }
}
