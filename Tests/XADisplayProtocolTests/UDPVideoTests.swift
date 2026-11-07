import XCTest

@testable import XADisplayProtocol

final class UDPVideoTests: XCTestCase {
    func testPacketizeReassembleAndFECRecovery() {
        let frame = Data((0..<2_500).map { UInt8($0 % 251) })
        var sequence: UInt16 = 7
        let packets = UDPVideoPacketizer.packetize(frame: frame, frameID: 3, nextSequence: &sequence, keyframe: true)
        XCTAssertGreaterThanOrEqual(packets.count, 3)
        XCTAssertTrue(packets.contains { $0.fec })
        XCTAssertEqual(packets.map { UDPVideoPacket.decode($0.encode()) }, packets)
        var ordered = UDPReassembler()
        var restored: Data?
        for packet in packets where !packet.fec {
            restored = ordered.ingest(packet) ?? restored
        }
        XCTAssertEqual(restored, frame)
        var lossy = UDPReassembler()
        var recovered: Data?
        for packet in packets where packet.fragmentIndex != 1 || packet.fec {
            recovered = lossy.ingest(packet) ?? recovered
        }
        XCTAssertEqual(recovered, frame)
    }

    func testNackNamesTheHoleAndIgnoresDuplicates() {
        func lone(_ sequence: UInt16) -> UDPVideoPacket {
            UDPVideoPacket(sequence: sequence, frameID: sequence, fragmentIndex: 0, fragmentCount: 1, keyframe: false, fec: false, payload: Data([UInt8(sequence)]))
        }
        var box = UDPReassembler()
        XCTAssertEqual(box.ingest(lone(1)), Data([1]))
        _ = box.ingest(lone(1))
        _ = box.ingest(lone(4))
        XCTAssertEqual(box.missing(), [2, 3])
    }

    func testWiFiTunerBacksOffAndDropsResolution() {
        var tuner = WiFiLinkTuner()
        XCTAssertEqual(tuner.bitrate, WiFiLinkTuner.startBitrate)
        var tune = tuner.observe(rttMs: 70, jitterMs: 5)
        XCTAssertLessThan(tune.bitrate, WiFiLinkTuner.startBitrate)
        tune = tuner.observe(rttMs: 100, jitterMs: 30)
        tune = tuner.observe(rttMs: 100, jitterMs: 30)
        XCTAssertEqual(tune.preset, .safe)
        for _ in 0..<12 { tune = tuner.observe(rttMs: 10, jitterMs: 2) }
        XCTAssertEqual(tune.preset, .balanced)
        XCTAssertLessThanOrEqual(tune.bitrate, WiFiLinkTuner.startBitrate)
        var jitter = JitterEstimate()
        XCTAssertEqual(jitter.add(sampleMs: 20), 0, accuracy: 0.01)
        XCTAssertEqual(jitter.add(sampleMs: 30), 2, accuracy: 0.01)
        XCTAssertFalse(WiFiPowerSave.publicAPIDisablesPowerSave)
        XCTAssertEqual(LowLatencyEncoderRequest.maxFrameDelayCount, 0)
        XCTAssertFalse(LowLatencyEncoderRequest.allowBFrames)
    }
}
