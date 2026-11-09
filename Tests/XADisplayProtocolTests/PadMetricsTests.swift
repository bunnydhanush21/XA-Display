import XCTest

@testable import XADisplayProtocol

final class PadMetricsTests: XCTestCase {
    func testEndToEndUsesTheClockOffsetAndExportNamesTheColumns() throws {
        let latency = PadMetricsMath.endToEndLatencyMilliseconds(captureHostMs: 1_000, displayedClientMs: 5_040, clientMinusHostMs: 4_000)
        XCTAssertEqual(latency ?? -1, 40, accuracy: 0.001)
        XCTAssertNil(PadMetricsMath.endToEndLatencyMilliseconds(captureHostMs: 1_000, displayedClientMs: 5_040, clientMinusHostMs: nil))
        var window = PadMetricsAccumulator()
        let start = Date()
        window.anchor(at: start)
        window.noteReceived(bytes: 100_000)
        window.noteReceived(bytes: 50_000)
        window.noteDropped()
        window.noteDisplayed(decodeMilliseconds: 4, captureHostMs: 1_000, displayedClientMs: 5_040, clientMinusHostMs: 4_000)
        let sample = window.snapshot(now: start.addingTimeInterval(1), inputRoundTripMilliseconds: 12)
        XCTAssertEqual(sample.receivedFramesPerSecond, 2, accuracy: 0.01)
        XCTAssertEqual(sample.displayedFramesPerSecond, 1, accuracy: 0.01)
        XCTAssertEqual(sample.droppedFrames, 1)
        XCTAssertEqual(sample.inboundBitsPerSecond, 1_200_000, accuracy: 1)
        XCTAssertEqual(sample.decodeTimeMilliseconds, 4, accuracy: 0.01)
        XCTAssertEqual(sample.endToEndLatencyMilliseconds ?? -1, 40, accuracy: 0.01)
        XCTAssertEqual(sample.inputRoundTripMilliseconds ?? -1, 12, accuracy: 0.01)
        let csv = PadMetricsExport.csv([sample])
        XCTAssertTrue(csv.contains("receivedFramesPerSecond,displayedFramesPerSecond,droppedFrames,inboundBitsPerSecond,decodeTimeMilliseconds,endToEndLatencyMilliseconds,inputRoundTripMilliseconds"))
        let json = try JSONSerialization.jsonObject(with: PadMetricsExport.json([sample])) as? [[String: Any]]
        XCTAssertEqual(json?.first?["droppedFrames"] as? Int, 1)
        let directory = NSTemporaryDirectory() + "xa-metrics-test"
        try PadMetricsExport.write([sample], directory: directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory + "/xa-metrics.json"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory + "/xa-metrics.csv"))
        XCTAssertTrue(PadMetricsText.pill(sample).contains("drop 1"))
    }
}
