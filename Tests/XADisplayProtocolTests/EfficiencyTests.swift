import Darwin
import XCTest

@testable import XADisplayProtocol

final class EfficiencyTests: XCTestCase {
    func testAnnexBScanMatchesParseAndWritesEachNALOnce() {
        let timing = Data("{\"type\":\"timing\",\"seq\":3,\"captureMs\":10,\"encodeMs\":1}".utf8)
        let nalus = [Data([0x67, 0x42]), Data([0x68, 0xCE]), Data([0x65, 0x11, 0x22])]
        let payload = AnnexB.encode(timingJSON: timing, nalus: nalus)
        let parsed = AnnexB.parse(payload)
        let scanned = AnnexBSpan.scan(payload)
        XCTAssertEqual(scanned.timing, parsed.timing)
        XCTAssertEqual(scanned.spans.count, parsed.nalus.count)
        XCTAssertFalse(scanned.truncated)
        for pair in zip(scanned.spans, parsed.nalus) {
            XCTAssertEqual(pair.0.type, pair.1.type)
            XCTAssertEqual(payload.subdata(in: pair.0.range), pair.1.data)
        }
        var avcc = Data(count: AnnexBSpan.avccByteCount(scanned.spans))
        let written = payload.withUnsafeBytes { raw in
            avcc.withUnsafeMutableBytes { AnnexBSpan.writeAVCC(source: raw, spans: scanned.spans, into: $0) }
        }
        XCTAssertEqual(written, avcc.count)
        XCTAssertEqual([UInt8](avcc.prefix(4)), [0, 0, 0, 2])
        let large = AnnexB.encode(timingJSON: nil, nalus: [Data(repeating: 0x41, count: 32_000)])
        let parseStart = Date()
        for _ in 0..<100 { _ = AnnexB.parse(large) }
        let parseSeconds = Date().timeIntervalSince(parseStart)
        let scanStart = Date()
        for _ in 0..<100 { _ = AnnexBSpan.scan(large) }
        let scanSeconds = Date().timeIntervalSince(scanStart)
        print("annexb parse_s=\(parseSeconds) scan_s=\(scanSeconds) bytes=\(large.count)")
        XCTAssertLessThanOrEqual(scanSeconds, parseSeconds * 3 + 0.05)
    }

    func testDecryptThroughputAtEightAndEighteenMegabits() {
        let token = "ABCD2345"
        let key = ChannelSeal.derivedKey(token: token, direction: .hostToPad)
        var seal = ChannelSeal(token: token, direction: .hostToPad)
        for megabits in [8, 18] {
            let frameBytes = megabits * 1_000_000 / 8 / 30
            let plain = Data(repeating: 0x5A, count: frameBytes)
            var frames: [Data] = []
            for _ in 0..<30 {
                guard let sealed = seal.seal(plain, aad: SealChannel.video.aad) else {
                    return XCTFail("seal")
                }
                frames.append(sealed)
            }
            let copyStart = Date()
            for frame in frames {
                XCTAssertEqual(ChannelSeal.copyingOpen(key: key, sealed: frame, aad: SealChannel.video.aad), plain)
            }
            let copySeconds = Date().timeIntervalSince(copyStart)
            var scratch = Data()
            let reuseStart = Date()
            for frame in frames {
                XCTAssertNotNil(ChannelSeal.open(key: key, sealed: frame, aad: SealChannel.video.aad, into: &scratch))
                XCTAssertEqual(scratch, plain)
            }
            let reuseSeconds = Date().timeIntervalSince(reuseStart)
            let reuseMbps = Double(frameBytes * frames.count * 8) / max(reuseSeconds, 0.000_001) / 1_000_000
            print("gcm \(megabits)Mb/s-equivalent copy_s=\(copySeconds) reuse_s=\(reuseSeconds) reuse_mbps=\(reuseMbps)")
            XCTAssertGreaterThan(reuseMbps, Double(megabits))
        }
    }

    func testSealPrefixedFrameIsOneBuffer() {
        var seal = ChannelSeal(token: "ABCD2345", direction: .hostToPad)
        let plain = Data([0, 0, 0, 1, 0x65, 0x11])
        guard let framed = seal.sealPrefixed(plain, aad: SealChannel.video.aad) else { return XCTFail("seal") }
        XCTAssertEqual(framed.count, 4 + ChannelSeal.overhead + plain.count)
        var parser = FrameParser(limits: .video)
        guard case .ok(let frames) = parser.append(framed, now: 1), let frame = frames.first else { return XCTFail("parse") }
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(ChannelSeal.open(token: "ABCD2345", sealed: frame, aad: SealChannel.video.aad), plain)
    }

    func testVideoSendQueueWritesOneBufferAndPacketizesUDP() {
        let queue = VideoSendQueue(seal: ChannelSeal(token: "ABCD2345", direction: .hostToPad))
        var descriptors = [Int32](repeating: 0, count: 2)
        XCTAssertEqual(Darwin.pipe(&descriptors), 0)
        queue.note(fd: descriptors[1])
        queue.flush()
        let wrote = expectation(description: "usb write")
        queue.submit(payload: Data([0, 0, 0, 1, 0x65]), aad: SealChannel.video.aad, udp: false, keyframe: true) { product in
            if case .idle = product { wrote.fulfill() }
        }
        wait(for: [wrote], timeout: 2)
        var buffer = [UInt8](repeating: 0, count: 64)
        let count = Darwin.read(descriptors[0], &buffer, buffer.count)
        XCTAssertGreaterThan(count, 4)
        close(descriptors[0])
        close(descriptors[1])
        let packetized = expectation(description: "udp")
        queue.submit(payload: Data([0, 0, 0, 1, 0x41]), aad: SealChannel.udp.aad, udp: true, keyframe: false) { product in
            if case .udp(let packets) = product {
                XCTAssertFalse(packets.isEmpty)
                packetized.fulfill()
            }
        }
        wait(for: [packetized], timeout: 2)
    }

    func testUIPaceAndMoveCoalesce() {
        var pace = UIPace(interval: 0.5)
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(pace.allow(now: start, force: false))
        XCTAssertFalse(pace.allow(now: start.addingTimeInterval(0.2), force: false))
        XCTAssertTrue(pace.allow(now: start.addingTimeInterval(0.2), force: true))
        XCTAssertTrue(pace.allow(now: start.addingTimeInterval(0.8), force: false))
        var gate = CoalesceGate<Int>()
        gate.offer(1)
        gate.offer(2)
        gate.offer(3)
        XCTAssertEqual(gate.take(), 3)
        XCTAssertNil(gate.take())
    }
}
