import XCTest

@testable import XADisplayProtocol

final class ArchitectureTests: XCTestCase {
    func testConnectionMachineAndBadge() {
        XCTAssertEqual(ConnectionMachine.reduce(.idle, .startDiscovery), .discovering)
        XCTAssertEqual(ConnectionMachine.reduce(.discovering, .beginConnect), .connecting)
        XCTAssertEqual(ConnectionMachine.reduce(.connecting, .transportReady), .pairing)
        XCTAssertEqual(ConnectionMachine.reduce(.pairing, .authAccepted), .streaming)
        XCTAssertEqual(ConnectionMachine.reduce(.streaming, .linkLost), .reconnecting)
        XCTAssertEqual(ConnectionMachine.reduce(.reconnecting, .transportReady), .pairing)
        XCTAssertEqual(ConnectionMachine.reduce(.pairing, .authRejected), .failed(.pairing))
        XCTAssertEqual(ConnectionMachine.reduce(.connecting, .linkLost), .failed(.transport))
        XCTAssertEqual(ConnectionMachine.reduce(.failed(.pairing), .retry), .discovering)
        XCTAssertEqual(ConnectionMachine.reduce(.streaming, .userStop), .idle)
        XCTAssertEqual(MenuBadge.name(for: .streaming), "green")
        XCTAssertEqual(MenuBadge.name(for: .connecting), "yellow")
        XCTAssertEqual(MenuBadge.name(for: .failed(.permission)), "red")
        let error = XAError.permission(.screenRecording)
        XCTAssertTrue(error.userMessage.contains("screenRecording"))
        XCTAssertTrue(error.recovery.contains("Screen Recording"))
    }

    func testChannelAuthGatesVideoAudioAndClipboard() {
        let empty = SHA256Box.hash([])
        XCTAssertEqual(empty.map { String(format: "%02x", $0) }.joined(), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        let proof = ChannelAuth.proof(token: "ABCD2345", channel: .video, nonce: "ipad")
        XCTAssertTrue(ChannelAuth.verify(token: "ABCD-2345", channel: .video, nonce: "ipad", proof: proof))
        XCTAssertFalse(ChannelAuth.verify(token: "ABCD2345", channel: .video, nonce: "other", proof: proof))
        var gate = ChannelGate(requireAuth: true)
        XCTAssertFalse(gate.allows(.video))
        XCTAssertFalse(gate.allows(.audio))
        XCTAssertTrue(gate.acceptVideo(token: "ABCD2345", nonce: "ipad", proof: proof))
        XCTAssertTrue(gate.allows(.video))
        XCTAssertFalse(gate.allows(.clipboard))
        gate.noteInputArmed(true)
        XCTAssertTrue(gate.allows(.audio))
        XCTAssertTrue(gate.allows(.clipboard))
        gate.reset()
        XCTAssertFalse(gate.allows(.video))
        let message = VideoControlMessage.xaAuth(id: "ipad", proof: proof)
        XCTAssertEqual(VideoControlMessage.parse(message.jsonData() ?? Data()), message)
    }

    func testCustomDisplayDiagnosticsAndFuzz() {
        let custom = CustomDisplaySettings(enabled: true, width: 10, height: 9000, fps: 120, bitrate: 1).clamped()
        XCTAssertEqual(custom.width, 640)
        XCTAssertEqual(custom.height, 4096)
        XCTAssertEqual(custom.fps, 60)
        XCTAssertEqual(custom.bitrate, 500_000)
        let sized = custom.applying(to: .balanced)
        XCTAssertEqual(sized.width, 640)
        XCTAssertEqual(sized.fps, 60)
        var document = XASettingsDocument.defaults
        document.set(.bool(true), for: "display.custom")
        document.set(.number(1280), for: "display.width")
        document.set(.number(8), for: "display.bitrate")
        let merged = SettingsSync.apply(SettingsSync.encode(document), to: XASettingsDocument.defaults)
        XCTAssertTrue(merged.features.custom.enabled)
        XCTAssertEqual(merged.features.custom.width, 1280)
        XCTAssertEqual(merged.features.custom.bitrate, 8_000_000)
        var ring = LogRing()
        ring.append("token ABCD2345 was used")
        XCTAssertFalse(ring.entries.joined().contains("ABCD"))
        let zip = StoredZip.archive(name: "diagnostics.txt", data: Data("ok".utf8))
        XCTAssertEqual([zip[0], zip[1], zip[2], zip[3]], [0x50, 0x4B, 0x03, 0x04])
        XCTAssertTrue(zip.contains(0x6F))
        XCTAssertTrue(StatsPill.heightFits(pill: 22, screen: 768))
        XCTAssertFalse(StatsPill.heightFits(pill: 80, screen: 768))
        var parser = FrameParser(limits: .input)
        var rng = SplitMix(seed: 0xA5A5)
        for _ in 0..<40 {
            var bytes = [UInt8]()
            let count = Int(rng.next() % 80)
            for _ in 0..<count { bytes.append(UInt8(rng.next() & 0xFF)) }
            _ = parser.append(Data(bytes), now: 1)
            _ = VideoControlMessage.parse(Data(bytes))
            _ = try? XAInputMessage.decode(Data(bytes))
        }
        XCTAssertLessThanOrEqual(parser.bufferedByteCount, FrameLimits.input.maxBuffer)
    }
}

private struct SplitMix {
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
