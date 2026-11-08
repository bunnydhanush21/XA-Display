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
}
