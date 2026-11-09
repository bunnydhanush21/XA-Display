import Foundation

/// A NAL unit as a range into the caller's buffer. The hot path does not copy the NAL bytes.
public struct NALSpan: Equatable, Sendable {
    public var start: Int
    public var count: Int
    public var type: Int

    public var range: Range<Int> { start..<(start + count) }

    public init(start: Int, count: Int, type: Int) {
        self.start = start
        self.count = count
        self.type = type
    }
}

/// In-place view of one Annex-B access unit.
public struct AnnexBView: Equatable, Sendable {
    public var timing: TimingPrefix?
    public var spans: [NALSpan]
    public var truncated: Bool

    public init(timing: TimingPrefix?, spans: [NALSpan], truncated: Bool) {
        self.timing = timing
        self.spans = spans
        self.truncated = truncated
    }
}

/// Scans Annex-B start codes and writes AVCC length prefixes without copying NAL payloads into `Data`.
public enum AnnexBSpan {
    public static func scan(_ payload: Data) -> AnnexBView {
        payload.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            let count = bytes.count
            var starts: [Int] = []
            if count >= 4 {
                var index = 0
                while index + 4 <= count {
                    if bytes[index] == 0, bytes[index + 1] == 0, bytes[index + 2] == 0, bytes[index + 3] == 1 {
                        starts.append(index)
                        index += 4
                    } else {
                        index += 1
                    }
                }
            }
            guard let first = starts.first else {
                return AnnexBView(timing: nil, spans: [], truncated: false)
            }
            var timing: TimingPrefix?
            if first > 0, first <= AnnexB.maxTimingPrefix {
                let prefix = Data(bytes[0..<first])
                timing = AnnexB.parseTiming(prefix)
            }
            var spans: [NALSpan] = []
            var truncated = false
            for index in 0..<starts.count {
                if spans.count >= AnnexB.maxNALUs {
                    truncated = true
                    break
                }
                let begin = starts[index] + 4
                let end = index + 1 < starts.count ? starts[index + 1] : count
                if begin < end {
                    spans.append(NALSpan(start: begin, count: end - begin, type: Int(bytes[begin] & 0x1F)))
                }
            }
            return AnnexBView(timing: timing, spans: spans, truncated: truncated)
        }
    }

    public static func avccByteCount(_ spans: [NALSpan]) -> Int {
        spans.reduce(0) { $0 + 4 + $1.count }
    }

    /// Writes each NAL once as a 4-byte big-endian length plus the NAL bytes. Returns the bytes written, or -1 if the destination is short.
    public static func writeAVCC(source: UnsafeRawBufferPointer, spans: [NALSpan], into destination: UnsafeMutableRawBufferPointer) -> Int {
        guard let sourceBase = source.baseAddress, let destBase = destination.baseAddress else { return spans.isEmpty ? 0 : -1 }
        var offset = 0
        for span in spans {
            let total = 4 + span.count
            guard span.start >= 0, span.count >= 0, span.start + span.count <= source.count, offset + total <= destination.count else { return -1 }
            var length = UInt32(span.count).bigEndian
            withUnsafeBytes(of: &length) { bytes in
                destBase.advanced(by: offset).copyMemory(from: bytes.baseAddress!, byteCount: 4)
            }
            destBase.advanced(by: offset + 4).copyMemory(from: sourceBase.advanced(by: span.start), byteCount: span.count)
            offset += total
        }
        return offset
    }
}
