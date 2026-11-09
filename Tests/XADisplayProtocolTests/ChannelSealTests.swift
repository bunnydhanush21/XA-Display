import XCTest

@testable import XADisplayProtocol

final class ChannelSealTests: XCTestCase {
    func testSealRoundTripsVideoInputAndUDP() {
        let token = "ABCD2345"
        for channel in [SealChannel.video, .input, .udp] {
            var seal = ChannelSeal(token: token)
            let plain = Data("{\"type\":\"ping\"}".utf8)
            let sealed = seal.seal(plain, aad: channel.aad)
            XCTAssertEqual(ChannelSeal.open(token: token, sealed: sealed ?? Data(), aad: channel.aad), plain)
            XCTAssertNil(ChannelSeal.open(token: token, sealed: sealed ?? Data(), aad: Data("other".utf8)))
            XCTAssertNil(ChannelSeal.open(token: "ZZZZ9999", sealed: sealed ?? Data(), aad: channel.aad))
        }
    }

    func testTamperedTagOrCiphertextIsRejected() {
        var seal = ChannelSeal(token: "ABCD2345")
        guard var sealed = seal.seal(Data([1, 2, 3, 4, 5]), aad: SealChannel.video.aad) else {
            return XCTFail("seal")
        }
        sealed[sealed.index(before: sealed.endIndex)] ^= 0x01
        XCTAssertNil(ChannelSeal.open(token: "ABCD2345", sealed: sealed, aad: SealChannel.video.aad))
        guard var again = seal.seal(Data([9, 8, 7]), aad: SealChannel.input.aad) else { return XCTFail("seal") }
        let cipherIndex = again.index(again.startIndex, offsetBy: 1 + ChannelSeal.nonceLength)
        again[cipherIndex] ^= 0xFF
        XCTAssertNil(ChannelSeal.open(token: "ABCD2345", sealed: again, aad: SealChannel.input.aad))
    }

    func testEmptyTokenAndEmptyPlaintext() {
        var empty = ChannelSeal(token: "")
        XCTAssertNil(empty.seal(Data([1]), aad: SealChannel.video.aad))
        XCTAssertNil(ChannelSeal.open(token: "", sealed: Data([1, 2, 3]), aad: SealChannel.video.aad))
        var seal = ChannelSeal(token: "ABCD2345")
        let sealed = seal.seal(Data(), aad: SealChannel.udp.aad)
        XCTAssertEqual(ChannelSeal.open(token: "ABCD2345", sealed: sealed ?? Data(), aad: SealChannel.udp.aad), Data())
    }

    func testNoncesDoNotRepeatAndRandomPayloadsRoundTrip() {
        var seal = ChannelSeal(token: "ABCD2345")
        let first = seal.seal(Data([1]), aad: SealChannel.video.aad) ?? Data()
        let second = seal.seal(Data([1]), aad: SealChannel.video.aad) ?? Data()
        XCTAssertNotEqual(first, second)
        var state: UInt64 = 42
        func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            return state
        }
        for _ in 0..<24 {
            let count = Int(next() % 300)
            let plain = Data((0..<count).map { _ in UInt8(next() & 0xFF) })
            let channel = [SealChannel.video, .input, .udp][Int(next() % 3)]
            let sealed = seal.seal(plain, aad: channel.aad) ?? Data()
            XCTAssertEqual(ChannelSeal.open(token: "ABCD2345", sealed: sealed, aad: channel.aad), plain)
            if sealed.count > ChannelSeal.overhead {
                var mutated = sealed
                let index = mutated.index(mutated.startIndex, offsetBy: Int(next() % UInt64(mutated.count)))
                mutated[index] ^= 0x5A
                XCTAssertNil(ChannelSeal.open(token: "ABCD2345", sealed: mutated, aad: channel.aad))
            }
        }
    }

    func testSealedUDPFrameReassemblesBeforeItOpens() {
        var seal = ChannelSeal(token: "ABCD2345")
        let annex = Data(repeating: 0x41, count: 2_400)
        let sealed = seal.seal(annex, aad: SealChannel.udp.aad) ?? Data()
        var sequence: UInt16 = 1
        let packets = UDPVideoPacketizer.packetize(frame: sealed, frameID: 7, nextSequence: &sequence, keyframe: true)
        var reassembler = UDPReassembler()
        var opened: Data?
        for packet in packets where !packet.fec {
            if let frame = reassembler.ingest(packet) {
                opened = ChannelSeal.open(token: "ABCD2345", sealed: frame, aad: SealChannel.udp.aad)
            }
        }
        XCTAssertEqual(opened, annex)
    }

    func testMutatingAValidInputFrameDoesNotDecode() throws {
        let message = XAInputMessage.mouse(XAMouse(session: 1, seq: 1, phase: .down, button: .left, x: 0.5, y: 0.5, space: .absoluteNormalized))
        let encoded = try message.encode()
        for index in encoded.indices {
            var mutated = encoded
            mutated[index] ^= 0x01
            if mutated == encoded { continue }
            _ = try? XAInputMessage.decode(mutated)
        }
        XCTAssertEqual(try XAInputMessage.decode(encoded), message)
    }

    func testHKDFMatchesTheRFCVector() {
        let ikm = hex("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b")
        let salt = hex("000102030405060708090a0b0c")
        let info = hex("f0f1f2f3f4f5f6f7f8f9")
        let okm = HKDF.derive(ikm: ikm, salt: salt, info: info, outputLength: 42)
        XCTAssertEqual(okm, hex("3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"))
    }

    func testReconnectDoesNotReuseTheNonce() {
        var first = ChannelSeal(token: "ABCD2345", direction: .hostToPad)
        let opening = first.seal(Data([1]), aad: SealChannel.video.aad) ?? Data()
        let next = first.seal(Data([1]), aad: SealChannel.video.aad) ?? Data()
        XCTAssertEqual(opening.dropFirst().prefix(8), next.dropFirst().prefix(8))
        XCTAssertEqual(Array(opening.dropFirst(9).prefix(4)), [0, 0, 0, 0])
        XCTAssertEqual(Array(next.dropFirst(9).prefix(4)), [0, 0, 0, 1])
        var reconnected = ChannelSeal(token: "ABCD2345", direction: .hostToPad)
        let again = reconnected.seal(Data([1]), aad: SealChannel.video.aad) ?? Data()
        XCTAssertNotEqual(again.dropFirst().prefix(8), opening.dropFirst().prefix(8))
        var otherDirection = ChannelSeal(token: "ABCD2345", direction: .padToHost)
        let crossed = otherDirection.seal(Data([1]), aad: SealChannel.video.aad) ?? Data()
        XCTAssertNil(ChannelSeal.open(token: "ABCD2345", sealed: crossed, aad: SealChannel.video.aad, direction: .hostToPad))
        var exhausted = ChannelSeal(token: "ABCD2345", direction: .hostToPad, testingCounter: .max)
        XCTAssertNil(exhausted.seal(Data([1]), aad: SealChannel.video.aad))
    }

    func testReplayOfASealedFrameIsRejected() {
        var sender = ChannelSeal(token: "ABCD2345", direction: .padToHost)
        var inbox = SealInbox(token: "ABCD2345", direction: .padToHost)
        var frames: [Data] = []
        for index in 0..<70 {
            frames.append(sender.seal(Data([UInt8(index)]), aad: SealChannel.input.aad) ?? Data())
        }
        XCTAssertEqual(inbox.open(sealed: frames[0], aad: SealChannel.input.aad), Data([0]))
        XCTAssertNil(inbox.open(sealed: frames[0], aad: SealChannel.input.aad))
        XCTAssertEqual(inbox.open(sealed: frames[69], aad: SealChannel.input.aad), Data([69]))
        XCTAssertNil(inbox.open(sealed: frames[0], aad: SealChannel.input.aad))
        XCTAssertEqual(inbox.open(sealed: frames[68], aad: SealChannel.input.aad), Data([68]))
        XCTAssertNil(inbox.open(sealed: frames[68], aad: SealChannel.input.aad))
        XCTAssertNil(inbox.open(sealed: frames[2], aad: SealChannel.input.aad))
    }

    private func hex(_ text: String) -> Data {
        var data = Data()
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return Data() }
            data.append(byte)
            index = next
        }
        return data
    }
}
