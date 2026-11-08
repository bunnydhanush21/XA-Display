import AVFoundation
import UIKit
import XADisplayProtocol
import XCTest

@testable import XADisplay

final class ComponentCoverageTests: XCTestCase {
    func testBatteryAudioLoupeAndSealedVideoFrame() {
        _ = BatteryRegistry.read()
        let loop = BatteryCareLoop()
        let idle = loop.tick(enabledTelemetry: true, chargeLimit: false, config: ChargeLimitConfig())
        let limited = loop.tick(enabledTelemetry: false, chargeLimit: true, config: ChargeLimitConfig())
        XCTAssertEqual(limited.text, "")
        _ = idle
        loop.restore()
        XCTAssertFalse(BatteryCareClient.send(.status))
        let player = PCMPlayer()
        player.start()
        player.setVolume(0.2)
        player.enqueue(Data(repeating: 1, count: 64))
        player.stop()
        player.enqueue(Data(repeating: 1, count: 8))
        let routed = RoutedAudioPlayer()
        routed.volume = 0.4
        routed.setClockOffset(2)
        routed.start()
        routed.push(XAAudio(session: 1, sampleRate: 48_000, channels: 2, pcm: Data(repeating: 0, count: 64), codec: .pcm))
        routed.stop()
        let loupe = DragLoupe()
        loupe.show(image: UIImage(), around: CGPoint(x: 4, y: 4), finger: CGPoint(x: 40, y: 80))
        loupe.hide()
        let receiver = VideoReceiver(displayLayer: AVSampleBufferDisplayLayer())
        receiver.setPairingToken("ABCD2345")
        var seal = ChannelSeal(token: "ABCD2345")
        let json = VideoControlMessage.ping(t: 3).jsonData() ?? Data()
        let sealed = seal.seal(json, aad: SealChannel.video.aad) ?? Data()
        XCTAssertEqual(receiver.openSealed(sealed, channel: .video), json)
        XCTAssertNil(receiver.openSealed(Data([0, 1, 2]), channel: .udp))
        receiver.sendFrame(json)
        XCTAssertFalse(PadError.seal.userMessage.isEmpty)
        XCTAssertFalse(PadError.malformed.userMessage.isEmpty)
        XCTAssertFalse(PadError.transport("down").userMessage.isEmpty)
    }
}
