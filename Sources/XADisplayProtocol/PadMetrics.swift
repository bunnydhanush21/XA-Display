import Foundation

/// One second of iPad stream measurements. Names say what was counted.
public struct PadStreamSample: Equatable, Codable, Sendable {
    public var receivedFramesPerSecond: Double
    public var displayedFramesPerSecond: Double
    public var droppedFrames: Int
    public var inboundBitsPerSecond: Double
    public var decodeTimeMilliseconds: Double
    public var endToEndLatencyMilliseconds: Double?
    public var inputRoundTripMilliseconds: Double?

    public init(
        receivedFramesPerSecond: Double, displayedFramesPerSecond: Double, droppedFrames: Int, inboundBitsPerSecond: Double, decodeTimeMilliseconds: Double,
        endToEndLatencyMilliseconds: Double?, inputRoundTripMilliseconds: Double?
    ) {
        self.receivedFramesPerSecond = receivedFramesPerSecond
        self.displayedFramesPerSecond = displayedFramesPerSecond
        self.droppedFrames = droppedFrames
        self.inboundBitsPerSecond = inboundBitsPerSecond
        self.decodeTimeMilliseconds = decodeTimeMilliseconds
        self.endToEndLatencyMilliseconds = endToEndLatencyMilliseconds
        self.inputRoundTripMilliseconds = inputRoundTripMilliseconds
    }
}

/// PadMetricsMath.
public enum PadMetricsMath {
    /// Host capture time versus iPad display time. `clientMinusHostMs` is the ping/pong offset (RTT/2).
    public static func endToEndLatencyMilliseconds(captureHostMs: Double, displayedClientMs: Double, clientMinusHostMs: Double?) -> Double? {
        guard let offset = clientMinusHostMs, captureHostMs.isFinite, displayedClientMs.isFinite, offset.isFinite else { return nil }
        let displayedAsHost = displayedClientMs - offset
        let latency = displayedAsHost - captureHostMs
        guard latency.isFinite, latency >= 0, latency < 10_000 else { return nil }
        return latency
    }
}

/// PadMetricsText.
public enum PadMetricsText {
    public static func pill(_ sample: PadStreamSample) -> String {
        let latency = sample.endToEndLatencyMilliseconds.map { String(format: "%.0f ms e2e", $0) } ?? "e2e —"
        let rtt = sample.inputRoundTripMilliseconds.map { String(format: "%.0f ms rtt", $0) } ?? "rtt —"
        let megabits = sample.inboundBitsPerSecond / 1_000_000
        return String(
            format: "  rx %.0f  shown %.0f  drop %d  %.1f Mb/s  %@  %@  ",
            sample.receivedFramesPerSecond, sample.displayedFramesPerSecond, sample.droppedFrames, megabits, latency, rtt
        )
    }
}

/// PadMetricsAccumulator.
public struct PadMetricsAccumulator {
    public private(set) var droppedFrames = 0
    private var received = 0
    private var displayed = 0
    private var bytes = 0
    private var decodeSum = 0.0
    private var decodeCount = 0
    private var latency: Double?
    private var windowStart = Date()

    public init() {}

    public mutating func anchor(at date: Date) { windowStart = date }

    public mutating func noteReceived(bytes: Int) {
        received += 1
        self.bytes += max(0, bytes)
    }

    public mutating func noteDropped() { droppedFrames += 1 }

    public mutating func noteDisplayed(decodeMilliseconds: Double, captureHostMs: Double?, displayedClientMs: Double, clientMinusHostMs: Double?) {
        displayed += 1
        if decodeMilliseconds >= 0, decodeMilliseconds < 5_000 {
            decodeSum += decodeMilliseconds
            decodeCount += 1
        }
        if let captureHostMs = captureHostMs {
            latency = PadMetricsMath.endToEndLatencyMilliseconds(captureHostMs: captureHostMs, displayedClientMs: displayedClientMs, clientMinusHostMs: clientMinusHostMs)
        }
    }

    public mutating func snapshot(now: Date, inputRoundTripMilliseconds: Double?) -> PadStreamSample {
        let seconds = max(now.timeIntervalSince(windowStart), 0.001)
        let sample = PadStreamSample(
            receivedFramesPerSecond: Double(received) / seconds,
            displayedFramesPerSecond: Double(displayed) / seconds,
            droppedFrames: droppedFrames,
            inboundBitsPerSecond: Double(bytes) * 8 / seconds,
            decodeTimeMilliseconds: decodeCount == 0 ? 0 : decodeSum / Double(decodeCount),
            endToEndLatencyMilliseconds: latency,
            inputRoundTripMilliseconds: inputRoundTripMilliseconds
        )
        received = 0
        displayed = 0
        bytes = 0
        decodeSum = 0
        decodeCount = 0
        windowStart = now
        return sample
    }
}

/// PadMetricsExport.
public enum PadMetricsExport {
    public static func csv(_ rows: [PadStreamSample]) -> String {
        var lines = ["receivedFramesPerSecond,displayedFramesPerSecond,droppedFrames,inboundBitsPerSecond,decodeTimeMilliseconds,endToEndLatencyMilliseconds,inputRoundTripMilliseconds"]
        for row in rows {
            lines.append(
                [
                    number(row.receivedFramesPerSecond), number(row.displayedFramesPerSecond), String(row.droppedFrames), number(row.inboundBitsPerSecond),
                    number(row.decodeTimeMilliseconds), optional(row.endToEndLatencyMilliseconds), optional(row.inputRoundTripMilliseconds)
                ].joined(separator: ",")
            )
        }
        return lines.joined(separator: "\n")
    }

    public static func json(_ rows: [PadStreamSample]) -> Data {
        (try? JSONEncoder().encode(rows)) ?? Data("[]".utf8)
    }

    public static func write(_ rows: [PadStreamSample], directory: String) throws {
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try json(rows).write(to: folder.appendingPathComponent("xa-metrics.json"))
        try Data(csv(rows).utf8).write(to: folder.appendingPathComponent("xa-metrics.csv"))
    }

    private static func number(_ value: Double) -> String { String(format: "%.3f", value) }
    private static func optional(_ value: Double?) -> String { value.map { number($0) } ?? "" }
}
