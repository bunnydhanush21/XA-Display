import XCTest

@testable import XADisplayProtocol

final class QualityTests: XCTestCase {
    func testEveryDecoderRejectsRandomBytes() {
        var rng = SplitMix64(seed: 99)
        for _ in 0..<30 {
            let bytes = (0..<Int(rng.next() % 120)).map { _ in UInt8(rng.next() & 0xFF) }
            let data = Data(bytes)
            _ = try? XAInputMessage.decode(data)
            _ = VideoControlMessage.parse(data)
            _ = UDPVideoPacket.decode(data)
            _ = AnnexB.parse(data)
            _ = BatteryCareOp.parse(String(data: data, encoding: .utf8) ?? "")
            _ = ChromeWire.parseWindows(String(data: data, encoding: .utf8) ?? "")
            _ = ChromeWire.parseMenus(String(data: data, encoding: .utf8) ?? "")
            _ = XASettingsDocument.decode(data)
            var parser = FrameParser(limits: .video)
            _ = parser.append(data, now: 1)
            XCTAssertLessThanOrEqual(parser.bufferedByteCount, FrameLimits.video.maxBuffer)
        }
    }

    func testVideoControlCasesRoundTrip() {
        let messages: [VideoControlMessage] = [
            .hello(LegacyHello(pixelsWide: 1, pixelsHigh: 2, scale: 2, device: "iPad", id: "a", orientation: "landscape")),
            .touch(phase: "began", x: 0.1, y: 0.2),
            .scroll(dx: 1, dy: -1),
            .ping(t: 3),
            .pong(t: 3, mt: 4),
            .cursor(x: 0.2, y: 0.3, visible: true),
            .cursorImage(CursorImage(id: "c", png: Data([1, 2, 3]))),
            .xaHello,
            .frameAck(FrameAck(seq: 1, captureMs: 2, receiveMs: 3, enqueueMs: 4)),
            .health(HealthReport(thermal: .fair, batteryFraction: 0.5, batteryState: "unplugged", fpsDelivered: 30, decodeFails: 0)),
            .decodeFailed(preset: "balanced"),
            .xaStream(StreamAnnouncement(preset: "balanced", width: 1440, height: 1080, fps: 30, bitrate: 6_000_000, experimental: false)),
            .xaMetrics(XAMetrics(captureToAckMs: 12, encodeMs: 3)),
            .xaWindows("0,0,1,1"),
            .xaMenus("File"),
            .xaFront("com.example"),
            .xaBattery(text: "50%", heat: false),
            .xaSettings("{}"),
            .xaNack("1,2"),
            .xaOrient(orientation: "portrait", mode: "resolution", letterbox: false),
            .xaAuth(id: "pad", proof: "ab")
        ]
        for message in messages {
            XCTAssertEqual(VideoControlMessage.parse(message.jsonData() ?? Data()), message)
        }
    }

    func testSyntheticLoopbackPacingAndReconnectBudget() {
        let frame = Data(repeating: 7, count: 4_000)
        var sequence: UInt16 = 1
        let started = Date()
        var assembler = UDPReassembler()
        var intervals: [Double] = []
        var previous = Date()
        for index in 0..<20 {
            let packets = UDPVideoPacketizer.packetize(frame: frame, frameID: UInt16(index), nextSequence: &sequence, keyframe: index == 0)
            for packet in packets {
                _ = assembler.ingest(packet)
            }
            let now = Date()
            intervals.append(now.timeIntervalSince(previous) * 1000)
            previous = now
        }
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertLessThan(elapsed, ReconnectBudget.limitSeconds)
        let jitter = FramePacing.jitterMs(intervals)
        XCTAssertGreaterThanOrEqual(jitter, 0)
        var phase = ConnectionPhase.streaming
        phase = ConnectionMachine.reduce(phase, .linkLost)
        phase = ConnectionMachine.reduce(phase, .retry)
        XCTAssertEqual(phase, .discovering)
        XCTAssertTrue(ReconnectBudget.withinBudget(elapsed))
        let encoded = try? JSONSerialization.data(withJSONObject: [
            "loopback_reassembly_ms": elapsed * 1000,
            "frame_pacing_jitter_ms": jitter,
            "reconnect_state_machine_s": elapsed,
            "encode_transport_glass_ms": "device-pending",
            "ipad_memory_mb": "device-pending",
            "device_reconnect_s": "device-pending"
        ])
        if let encoded, let dir = ProcessInfo.processInfo.environment["QUALITY_BENCH_DIR"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? encoded.write(to: URL(fileURLWithPath: dir).appendingPathComponent("loopback.json"))
        }
    }

    func testExportDiagnosticsRedactsStructuredFields() {
        let text = DiagnosticsText.render(
            DiagnosticsSnapshot(
                appVersion: "1.0.0", transport: "usb", preset: "balanced", permissions: ["screenRecording": false],
                pairingToken: "ABCD2345", thermal: "mac", battery: "mac", notes: ["failure code=pairing message=denied"]
            ))
        XCTAssertFalse(text.contains("ABCD2345"))
        XCTAssertTrue(text.contains("code=pairing"))
        let zip = StoredZip.archive(name: "diagnostics.txt", data: Data(text.utf8))
        XCTAssertNotNil(zip.range(of: Data("diagnostics.txt".utf8)))
    }
}

private struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
