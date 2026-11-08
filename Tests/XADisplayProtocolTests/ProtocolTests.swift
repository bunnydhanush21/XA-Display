import XCTest

@testable import XADisplayProtocol

final class ProtocolTests: XCTestCase {
    func testLengthPrefixRoundTripAndSplitReads() {
        var parser = FrameParser(limits: .input)
        let payload = Data([1, 2, 3, 4, 5])
        let frame = LengthPrefixedFraming.encode(payload)
        let first = parser.append(Data(frame.prefix(2)), now: 0)
        guard case .ok(let none) = first else { return XCTFail("expected ok") }
        XCTAssertTrue(none.isEmpty)
        XCTAssertEqual(parser.bufferedByteCount, 2)
        let second = parser.append(Data(frame.dropFirst(2)), now: 0.1)
        guard case .ok(let frames) = second else { return XCTFail("expected frames") }
        XCTAssertEqual(frames, [payload])
        XCTAssertEqual(parser.bufferedByteCount, 0)
    }

    func testOversizedLengthDoesNotGrowTheBuffer() {
        var parser = FrameParser(limits: .video)
        let evil = Data([0x7F, 0xFF, 0xFF, 0xFF])
        let result = parser.append(evil, now: 0)
        XCTAssertEqual(result, .failed(.payloadTooLarge(declared: 0x7FFFFFFF, max: FrameLimits.video.maxPayload)))
        XCTAssertEqual(parser.bufferedByteCount, 0)
    }

    func testBufferCapRejectsAFlood() {
        var parser = FrameParser(limits: FrameLimits(maxPayload: 100, maxBuffer: 50))
        let flood = Data(repeating: 0, count: 80)
        let result = parser.append(flood, now: 0)
        XCTAssertEqual(result, .failed(.bufferTooLarge(80)))
        XCTAssertEqual(parser.bufferedByteCount, 0)
    }

    func testIncompleteFrameExpires() {
        var parser = FrameParser(limits: FrameLimits(maxPayload: 100, maxBuffer: 200, partialTimeout: 2))
        var header = UInt32(20).bigEndian
        let declared = withUnsafeBytes(of: &header) { Data($0) }
        XCTAssertEqual(parser.append(declared + Data([1, 2, 3]), now: 0), .ok([]))
        XCTAssertEqual(parser.tick(now: 1.9), .ok([]))
        XCTAssertEqual(parser.tick(now: 2), .failed(.incompleteExpired))
        XCTAssertEqual(parser.bufferedByteCount, 0)
    }

    func testEmptyLengthIsFatal() {
        var parser = FrameParser(limits: .input)
        XCTAssertEqual(parser.append(Data([0, 0, 0, 0]), now: 0), .failed(.emptyPayload))
    }

    func testFuzzParserStaysBounded() {
        var rng = LCG(state: 0xC0FFEE)
        var parser = FrameParser(limits: .video)
        for step in 0..<400 {
            let count = Int(rng.next() % 180)
            var chunk = Data(count: count)
            for index in 0..<count {
                chunk[index] = UInt8(rng.next() & 0xFF)
            }
            let outcome = parser.append(chunk, now: Double(step) * 0.01)
            XCTAssertLessThanOrEqual(parser.bufferedByteCount, FrameLimits.video.maxBuffer)
            if case .failed = outcome {
                parser = FrameParser(limits: .video)
            }
        }
    }

    func testInputCodecRoundTripAndFuzz() throws {
        let samples: [XAInputMessage] = [
            .hello(XAHello(protocolVersion: 1, token: "ABCD-EFGH", deviceName: "iPad", deviceID: "id-1")),
            .helloAck(XAHelloAck(accepted: false, session: 0, reason: "token")),
            .mouse(XAMouse(session: 7, seq: 3, phase: .down, button: .right, x: 0.25, y: 0.5, space: .absoluteNormalized)),
            .scroll(XAScroll(session: 7, seq: 4, dxPixels: -3.5, dyPixels: 12, inertia: true)),
            .key(XAKey(session: 7, seq: 5, phase: .typed, keyCode: 6, modifiers: [.command, .shift], text: "héllo")),
            .modifier(XAModifier(session: 7, seq: 6, mask: .command, down: true)),
            .ping(XAPing(session: 0, clientUnixMs: 1_700_000_000_000)),
            .pong(XAPong(session: 7, clientUnixMs: 10, hostUnixMs: 12)),
            .release(XARelease(session: 7, seq: 9)),
            .clipboard(XAClipboard(session: 7, seq: 10, revision: 3, text: "copied")),
            .window(XAWindowCommand(session: 7, seq: 11, action: .snapLeft)),
            .audio(XAAudio(session: 7, sampleRate: 48_000, channels: 2, pcm: Data([1, 2, 3, 4])))
        ]
        for sample in samples {
            let data = try sample.encode()
            XCTAssertEqual(try XAInputMessage.decode(data), sample)
        }
        var rng = LCG(state: 99)
        for _ in 0..<200 {
            let count = Int(rng.next() % 80)
            var junk = Data(count: count)
            for index in 0..<count { junk[index] = UInt8(rng.next() & 0xFF) }
            do {
                _ = try XAInputMessage.decode(junk)
            } catch {
                XCTAssertTrue(error is ProtocolError)
            }
        }
    }

    func testUnknownInputTypeIsSkippedWithoutDesync() throws {
        var writer = ByteWriter()
        writer.u8(1)
        writer.u8(99)
        writer.u16(0)
        writer.u32(2)
        writer.u8(1)
        writer.u8(2)
        XCTAssertNil(try XAInputMessage.decode(writer.data))
        let message = XAInputMessage.mouse(XAMouse(session: 1, seq: 1, phase: .up, button: .left, x: 0, y: 0, space: .absoluteNormalized))
        XCTAssertEqual(try XAInputMessage.decode(try message.encode()), message)
    }

    func testLegacyHelloOmitsProtocolVersionField() throws {
        let data = try XCTUnwrap(
            VideoControlMessage.hello(
                LegacyHello(
                    pixelsWide: 2048, pixelsHigh: 1536, scale: 2, device: "iPad", id: "abc", orientation: "landscape"
                )
            ).jsonData())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["pv"])
        XCTAssertEqual(object["type"] as? String, "hello")
        if case .hello(let hello) = VideoControlMessage.parse(data) {
            XCTAssertEqual(hello.pixelsWide, 2048)
            XCTAssertEqual(hello.orientation, "landscape")
        } else {
            XCTFail("expected hello")
        }
    }

    func testOversizedCursorImageIsIgnored() {
        let png = Data(repeating: 1, count: VideoControlMessage.maxCursorPNG + 1)
        let object: [String: Any] = ["type": "cursorImg", "id": "big", "png": png.base64EncodedString()]
        let data = try! JSONSerialization.data(withJSONObject: object)
        XCTAssertEqual(VideoControlMessage.parse(data), .ignored)
    }

    func testTimingPrefixIsKept() {
        let timing = try! JSONSerialization.data(withJSONObject: ["type": "timing", "seq": 4, "captureMs": 1000.0, "encodeMs": 3.5])
        let idr = Data([0x65, 0x88])
        let payload = AnnexB.encode(timingJSON: timing, nalus: [idr])
        XCTAssertEqual(PayloadKind.classify(payload), .videoAccessUnit)
        let unit = AnnexB.parse(payload)
        XCTAssertEqual(unit.timing, TimingPrefix(seq: 4, captureMs: 1000, encodeMs: 3.5))
        XCTAssertTrue(unit.isKeyframe)
        XCTAssertFalse(unit.truncated)
    }

    func testAnnexBCapsNALUCount() {
        var nalus: [Data] = []
        for _ in 0..<80 { nalus.append(Data([0x61, 0x00])) }
        let unit = AnnexB.parse(AnnexB.encode(timingJSON: nil, nalus: nalus))
        XCTAssertEqual(unit.nalus.count, AnnexB.maxNALUs)
        XCTAssertTrue(unit.truncated)
    }
}

struct LCG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1
        return state
    }
}
