import XADisplayProtocol
@preconcurrency import XCTest

final class HostSmokeTests: XCTestCase {
    func testSessionPhasesAndChannelGate() {
        var phase = ConnectionPhase.idle
        for event in [ConnectionEvent.startDiscovery, .beginConnect, .transportReady, .authAccepted] {
            phase = ConnectionMachine.reduce(phase, event)
        }
        XCTAssertEqual(phase, .streaming)
        XCTAssertEqual(MenuBadge.name(for: phase), "green")
        var gate = ChannelGate(requireAuth: true)
        let proof = ChannelAuth.proof(token: "ABCD2345", channel: .video, nonce: "pad")
        XCTAssertTrue(gate.acceptVideo(token: "ABCD2345", nonce: "pad", proof: proof))
        XCTAssertTrue(gate.allows(.video))
        XCTAssertFalse(gate.allows(.audio))
        let zip = StoredZip.archive(name: "diagnostics.txt", data: Data("redacted".utf8))
        XCTAssertEqual(Array(zip.prefix(4)), [0x50, 0x4B, 0x03, 0x04])
    }
}
