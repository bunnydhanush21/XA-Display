import XCTest

@testable import XADisplayProtocol

final class SessionHandshakeTests: XCTestCase {
    func testHandshakeAgreesAndTheTokenCannotOpenTheFrame() {
        let started = Date()
        guard let client = SessionHandshake.clientOffer() else { return XCTFail("offer") }
        var replay = HandshakeReplayGuard()
        guard let host = SessionHandshake.hostAnswer(token: "ABCD2345", offer: client.frame, replay: &replay) else { return XCTFail("answer") }
        guard let finished = SessionHandshake.clientFinish(token: "ABCD2345", state: client.state, reply: host.reply) else { return XCTFail("finish") }
        guard let confirmed = SessionHandshake.hostConfirm(token: "ABCD2345", state: host.state, finish: finished.finish) else { return XCTFail("confirm") }
        XCTAssertEqual(finished.keys, confirmed)
        let elapsed = Date().timeIntervalSince(started) * 1000
        XCTAssertLessThan(elapsed, 500, "handshake \(String(format: "%.1f", elapsed)) ms")
        var seal = ChannelSeal(rawKey: confirmed.hostToPad, connectionID: client.state.party.connectionID)
        let sealed = seal.seal(Data("frame".utf8), aad: SealChannel.video.aad) ?? Data()
        var inbox = SealInbox(rawKey: confirmed.hostToPad)
        XCTAssertEqual(inbox.open(sealed: sealed, aad: SealChannel.video.aad), Data("frame".utf8))
        XCTAssertNil(ChannelSeal.open(token: "ABCD2345", sealed: sealed, aad: SealChannel.video.aad, direction: .hostToPad))
    }

    func testWrongTokenTamperedKeyAndReplayFail() {
        guard let client = SessionHandshake.clientOffer() else { return XCTFail("offer") }
        var replay = HandshakeReplayGuard()
        guard let host = SessionHandshake.hostAnswer(token: "ABCD2345", offer: client.frame, replay: &replay) else { return XCTFail("answer") }
        XCTAssertNil(SessionHandshake.clientFinish(token: "ZZZZ9999", state: client.state, reply: host.reply))
        var tampered = host.reply
        tampered[tampered.index(tampered.startIndex, offsetBy: 10)] ^= 0x01
        XCTAssertNil(SessionHandshake.clientFinish(token: "ABCD2345", state: client.state, reply: tampered))
        XCTAssertNil(SessionHandshake.hostAnswer(token: "ABCD2345", offer: client.frame, replay: &replay))
        guard let finished = SessionHandshake.clientFinish(token: "ABCD2345", state: client.state, reply: host.reply) else { return XCTFail("finish") }
        var badFinish = finished.finish
        badFinish[badFinish.index(before: badFinish.endIndex)] ^= 0xFF
        XCTAssertNil(SessionHandshake.hostConfirm(token: "ABCD2345", state: host.state, finish: badFinish))
    }

    func testHandshakeParserRejectsRandomBytes() {
        var state: UInt64 = 9
        func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            return state
        }
        for _ in 0..<32 {
            let count = Int(next() % 180)
            let bytes = Data((0..<count).map { _ in UInt8(next() & 0xFF) })
            if !SessionHandshake.isHandshake(bytes) {
                XCTAssertFalse(SessionHandshake.parse(bytes))
            }
            var replay = HandshakeReplayGuard()
            XCTAssertNil(SessionHandshake.hostAnswer(token: "ABCD2345", offer: bytes, replay: &replay))
        }
    }
}
