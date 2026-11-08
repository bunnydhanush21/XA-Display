import Foundation

/// UDPVideoPacket.
public struct UDPVideoPacket: Equatable {
    public static let magic: UInt8 = 0xA5
    public static let version: UInt8 = 1
    public static let maxPayload = 1_100
    public var sequence: UInt16
    public var frameID: UInt16
    public var fragmentIndex: UInt8
    public var fragmentCount: UInt8
    public var keyframe: Bool
    public var fec: Bool
    public var payload: Data
    public var lengths: [UInt16]

    public init(sequence: UInt16, frameID: UInt16, fragmentIndex: UInt8, fragmentCount: UInt8, keyframe: Bool, fec: Bool, payload: Data, lengths: [UInt16] = []) {
        self.sequence = sequence
        self.frameID = frameID
        self.fragmentIndex = fragmentIndex
        self.fragmentCount = fragmentCount
        self.keyframe = keyframe
        self.fec = fec
        self.payload = payload
        self.lengths = lengths
    }

    public func encode() -> Data {
        var data = Data(capacity: 10 + payload.count + lengths.count * 2)
        data.append(Self.magic)
        data.append(Self.version)
        var flags: UInt8 = 0
        if keyframe { flags |= 1 }
        if fec { flags |= 2 }
        data.append(flags)
        data.append(UInt8(frameID >> 8))
        data.append(UInt8(frameID & 0xFF))
        data.append(fragmentIndex)
        data.append(fragmentCount)
        data.append(UInt8(sequence >> 8))
        data.append(UInt8(sequence & 0xFF))
        if fec {
            data.append(UInt8(lengths.count))
            for length in lengths {
                data.append(UInt8(length >> 8))
                data.append(UInt8(length & 0xFF))
            }
        }
        data.append(payload)
        return data
    }

    public static func decode(_ data: Data) -> UDPVideoPacket? {
        guard data.count >= 9, data[0] == magic, data[1] == version else { return nil }
        let flags = data[2]
        let frameID = UInt16(data[3]) << 8 | UInt16(data[4])
        let index = data[5]
        let count = data[6]
        let sequence = UInt16(data[7]) << 8 | UInt16(data[8])
        let fec = flags & 2 != 0
        var offset = 9
        var lengths: [UInt16] = []
        if fec {
            guard offset < data.count else { return nil }
            let n = Int(data[offset])
            offset += 1
            guard data.count >= offset + n * 2 else { return nil }
            for _ in 0..<n {
                let length = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
                lengths.append(length)
                offset += 2
            }
        }
        return UDPVideoPacket(
            sequence: sequence, frameID: frameID, fragmentIndex: index, fragmentCount: count,
            keyframe: flags & 1 != 0, fec: fec, payload: data.subdata(in: offset..<data.count), lengths: lengths
        )
    }
}

/// UDPVideoPacketizer.
public enum UDPVideoPacketizer {
    public static func packetize(frame: Data, frameID: UInt16, nextSequence: inout UInt16, keyframe: Bool) -> [UDPVideoPacket] {
        guard !frame.isEmpty else { return [] }
        var chunks: [Data] = []
        var offset = 0
        while offset < frame.count {
            let end = min(frame.count, offset + UDPVideoPacket.maxPayload)
            chunks.append(frame.subdata(in: offset..<end))
            offset = end
        }
        guard chunks.count <= 255 else { return [] }
        var packets: [UDPVideoPacket] = []
        for (index, chunk) in chunks.enumerated() {
            packets.append(
                UDPVideoPacket(
                    sequence: nextSequence, frameID: frameID, fragmentIndex: UInt8(index), fragmentCount: UInt8(chunks.count),
                    keyframe: keyframe, fec: false, payload: chunk
                ))
            nextSequence &+= 1
        }
        guard chunks.count >= 2 else { return packets }
        let width = chunks.map(\.count).max() ?? 0
        var mixed = Data(count: width)
        for chunk in chunks {
            for index in 0..<chunk.count { mixed[index] ^= chunk[index] }
        }
        let lengths = chunks.map { UInt16($0.count) }
        packets.append(
            UDPVideoPacket(
                sequence: nextSequence, frameID: frameID, fragmentIndex: 0, fragmentCount: UInt8(chunks.count),
                keyframe: keyframe, fec: true, payload: mixed, lengths: lengths
            ))
        nextSequence &+= 1
        return packets
    }
}

/// UDPReassembler.
public struct UDPReassembler {
    private struct Buffer {
        var count: Int
        var parts: [UInt8: Data] = [:]
        var fec: Data?
        var lengths: [UInt16] = []
        var keyframe = false
    }

    private var frames: [UInt16: Buffer] = [:]
    private var seen = Set<UInt16>()
    private var order: [UInt16] = []
    public var highest: UInt16 = 0
    public var haveHighest = false
    private var base: UInt16 = 0
    private var haveBase = false

    public init() {}

    public mutating func ingest(_ packet: UDPVideoPacket) -> Data? {
        remember(packet.sequence)
        var buffer = frames[packet.frameID] ?? Buffer(count: Int(packet.fragmentCount))
        buffer.count = Int(packet.fragmentCount)
        buffer.keyframe = buffer.keyframe || packet.keyframe
        if packet.fec {
            buffer.fec = packet.payload
            buffer.lengths = packet.lengths
        } else {
            buffer.parts[packet.fragmentIndex] = packet.payload
        }
        if let frame = assemble(&buffer) {
            frames[packet.frameID] = nil
            return frame
        }
        frames[packet.frameID] = buffer
        if frames.count > 8, let oldest = frames.keys.sorted(by: { seqBefore($0, $1) }).first {
            frames[oldest] = nil
        }
        return nil
    }

    public func missing(limit: Int = 8) -> [UInt16] {
        guard haveBase, haveHighest, limit > 0 else { return [] }
        var holes: [UInt16] = []
        var cursor = base
        while cursor != highest && holes.count < limit {
            cursor &+= 1
            if cursor != highest && !seen.contains(cursor) { holes.append(cursor) }
        }
        return holes
    }

    private mutating func assemble(_ buffer: inout Buffer) -> Data? {
        if buffer.parts.count < buffer.count, let fec = buffer.fec, buffer.lengths.count == buffer.count, buffer.parts.count == buffer.count - 1 {
            guard let missing = (0..<buffer.count).first(where: { buffer.parts[UInt8($0)] == nil }) else { return nil }
            var mixed = fec
            for part in buffer.parts.values {
                let limit = min(part.count, mixed.count)
                for index in 0..<limit { mixed[index] ^= part[index] }
            }
            let length = Int(buffer.lengths[missing])
            guard length <= mixed.count else { return nil }
            buffer.parts[UInt8(missing)] = mixed.prefix(length)
        }
        guard buffer.parts.count == buffer.count else { return nil }
        var frame = Data()
        for index in 0..<buffer.count {
            guard let part = buffer.parts[UInt8(index)] else { return nil }
            frame.append(part)
        }
        return frame
    }

    private mutating func remember(_ sequence: UInt16) {
        if !haveBase {
            base = sequence
            haveBase = true
        }
        if !haveHighest || seqBefore(highest, sequence) { highest = sequence }
        haveHighest = true
        if seen.insert(sequence).inserted {
            order.append(sequence)
            if order.count > 64 {
                seen.remove(order.removeFirst())
            }
        }
    }

    private func seqBefore(_ lhs: UInt16, _ rhs: UInt16) -> Bool {
        Int16(bitPattern: rhs &- lhs) > 0
    }
}

/// JitterEstimate.
public struct JitterEstimate: Equatable {
    public private(set) var valueMs: Double = 0
    private var last: Double?
    public init() {}
    public mutating func add(sampleMs: Double) -> Double {
        guard sampleMs.isFinite, sampleMs >= 0 else { return valueMs }
        if let last = last {
            let delta = abs(sampleMs - last)
            valueMs = valueMs * 0.8 + delta * 0.2
        }
        last = sampleMs
        return valueMs
    }
}

/// WiFiLinkTune.
public struct WiFiLinkTune: Equatable {
    public var bitrate: Int
    public var preset: StreamPreset.ID
    public var changed: Bool
}

/// 802.11n starting point. These are controller targets, not measured throughput.
public struct WiFiLinkTuner: Equatable {
    public static let startBitrate = 6_000_000
    public static let floorBitrate = 2_000_000
    public private(set) var bitrate: Int
    public private(set) var preset: StreamPreset.ID
    public private(set) var preferred: StreamPreset.ID
    private var bad = 0
    private var good = 0

    public init(preferred: StreamPreset.ID = .balanced) {
        self.preferred = preferred == .native ? .balanced : preferred
        self.preset = self.preferred
        self.bitrate = Self.startBitrate
    }

    public mutating func observe(rttMs: Double, jitterMs: Double) -> WiFiLinkTune {
        let beforeBitrate = bitrate
        let beforePreset = preset
        let congested = rttMs > 50 || jitterMs > 12
        let severe = rttMs > 90 || jitterMs > 25
        if congested {
            good = 0
            bad += severe ? 2 : 1
            bitrate = max(Self.floorBitrate, bitrate * 8 / 10)
            if bad >= 3, preset == .balanced { preset = .safe }
        } else if rttMs < 25, jitterMs < 8 {
            bad = 0
            good += 1
            if good >= 8, bitrate < Self.startBitrate {
                bitrate = min(Self.startBitrate, bitrate * 10 / 8)
            }
            if good >= 12, preset == .safe, preferred == .balanced { preset = .balanced }
        }
        return WiFiLinkTune(bitrate: bitrate, preset: preset, changed: bitrate != beforeBitrate || preset != beforePreset)
    }
}

/// WiFiPowerSave.
public enum WiFiPowerSave {
    /// iOS does not offer a public switch for 802.11 power save. A short keepalive is the avoidance we can do.
    public static let publicAPIDisablesPowerSave = false
    public static let keepaliveSeconds = 0.2
}

/// LowLatencyEncoderRequest.
public enum LowLatencyEncoderRequest {
    public static let maxFrameDelayCount = 0
    public static let allowBFrames = false
    public static let intraRefreshKey = "EnablePeriodicIntraRefresh"
    public static let sliceBytesKey = "MaxH264SliceBytes"
    public static let sliceBytes = 1_200
}
