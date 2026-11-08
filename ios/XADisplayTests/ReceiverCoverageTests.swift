import AVFoundation
import UIKit
import XADisplayProtocol
import XCTest

@testable import XADisplay

final class ReceiverCoverageTests: XCTestCase {
    func testVideoControlMappingAndAnnexB() {
        let receiver = VideoReceiver(displayLayer: AVSampleBufferDisplayLayer())
        let delegate = VideoDelegateBox()
        receiver.delegate = delegate
        receiver.devicePixelsWide = 1440
        receiver.devicePixelsHigh = 1080
        let messages: [VideoControlMessage] = [
            .xaHello,
            .ping(t: 1),
            .cursor(x: 0.4, y: 0.6, visible: true),
            .xaStream(StreamAnnouncement(preset: "balanced", width: 1440, height: 1080, fps: 30, bitrate: 8_000_000, experimental: false)),
            .xaMetrics(XAMetrics(captureToAckMs: 12, encodeMs: 3)),
            .xaWindows("[]"),
            .xaMenus("[]"),
            .xaFront("com.apple.finder"),
            .xaOrient(orientation: "portrait", mode: "stream", letterbox: false),
            .xaOrient(orientation: "landscape", mode: "resolution", letterbox: true)
        ]
        receiver.queue.sync {
            for message in messages {
                receiver.handle(message.jsonData() ?? Data())
            }
            receiver.handle(Data([0x00]))
            receiver.resetStream()
            receiver.holdPictureUntilKeyframe()
            receiver.releasePictureHold()
        }
        receiver.xaHost = true
        receiver.sendAuth(id: "pad", token: "ABCD2345")
        receiver.sendSettings(SettingsSync.encode(.defaults))
        receiver.sendBattery(text: "80%", heat: false)
        receiver.sendHealth(HealthReport(thermal: .nominal, batteryFraction: 0.5, batteryState: "charging", fpsDelivered: 30, decodeFails: 0))
        receiver.sendDecodeFailed(preset: "balanced")
        receiver.sendTouch(phase: "ended", x: 0.1, y: 0.2)
        receiver.sendScroll(dx: 1, dy: -1)
        receiver.announcePanel()
        receiver.sendOrientation("portrait", mode: "stream")
        receiver.setStatus("listening")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertGreaterThanOrEqual(delegate.events, 1)
    }

    func testInputChannelMessagesAndLocalSettings() {
        let channel = InputChannel()
        let box = InputDelegateBox()
        let ready = expectation(description: "ack")
        box.onAck = { ready.fulfill() }
        channel.delegate = box
        channel.token = "ABCD2345"
        let now = UInt64(Date().timeIntervalSince1970 * 1000)
        channel.queue.sync {
            channel.handle(.helloAck(XAHelloAck(accepted: true, session: 7, reason: "ok")))
            XCTAssertTrue(channel.armed)
            channel.handle(.pong(XAPong(session: 7, clientUnixMs: now > 20 ? now - 20 : 0, hostUnixMs: now > 10 ? now - 10 : 0)))
            channel.handle(.clipboard(XAClipboard(session: 7, seq: 1, revision: 2, text: "copied")))
            channel.handle(.audio(XAAudio(session: 7, sampleRate: 48_000, channels: 2, pcm: Data([0, 1, 2, 3]))))
            channel.handle(.nowPlaying(XANowPlaying(session: 7, appName: "Music", title: "Track")))
            channel.handle(.release(XARelease(session: 7, seq: 2)))
        }
        channel.send(intent: .mouse(phase: .down, button: .left, x: 0.5, y: 0.5, space: .absoluteNormalized))
        channel.sendClipboard(text: "out", revision: 3)
        channel.sendMedia(.playPause, scrub: 0)
        channel.sendWindow(.snapLeft)
        channel.sendPing()
        channel.sendRelease()
        channel.pause()
        wait(for: [ready], timeout: 2)
        LocalSettings.save(token: "ABCD2345", features: XAFeatureSettings())
        let loaded = LocalSettings.load()
        XCTAssertEqual(loaded.token, "ABCD2345")
        LocalSettings.saveAssist(TouchAssist())
        _ = LocalSettings.loadAssist()
        LocalSettings.saveDocument(.defaults)
        _ = LocalSettings.loadDocument(features: XAFeatureSettings(), assist: TouchAssist())
        LocalSettings.saveMacs(MacDirectory())
        _ = LocalSettings.loadMacs()
        XCTAssertTrue(box.sawAck)
    }

}

private final class VideoDelegateBox: VideoReceiverDelegate {
    var events = 0
    func videoReceiver(_ receiver: VideoReceiver, statusDidChange status: String) { events += 1 }
    func videoReceiver(_ receiver: VideoReceiver, connected: Bool, transport: TransportKind) { events += 1 }
    func videoReceiver(_ receiver: VideoReceiver, videoSizeDidChange size: CGSize) { events += 1 }
    func videoReceiver(_ receiver: VideoReceiver, cursor point: CGPoint, visible: Bool) { events += 1 }
    func videoReceiver(_ receiver: VideoReceiver, cursorImage image: UIImage, id: String) { events += 1 }
    func videoReceiver(_ receiver: VideoReceiver, stats: ReceiverStats) { events += 1 }
    func videoReceiverBecameXAHost(_ receiver: VideoReceiver) { events += 1 }
    func videoReceiver(_ receiver: VideoReceiver, stream: StreamAnnouncement) { events += 1 }
    func videoReceiver(_ receiver: VideoReceiver, metrics: XAMetrics) { events += 1 }
    func videoReceiver(_ receiver: VideoReceiver, windows body: String) { events += 1 }
    func videoReceiver(_ receiver: VideoReceiver, menus body: String) { events += 1 }
    func videoReceiver(_ receiver: VideoReceiver, frontBundle bundle: String) { events += 1 }
    func videoReceiver(_ receiver: VideoReceiver, orientation: String, mode: String, letterbox: Bool) { events += 1 }
}

private final class InputDelegateBox: InputChannelDelegate {
    var sawAck = false
    var onAck: (() -> Void)?
    func inputChannel(_ channel: InputChannel, armed: Bool, reason: String) {
        sawAck = armed
        onAck?()
    }
    func inputChannel(_ channel: InputChannel, clipboard text: String, revision: UInt64) {}
    func inputChannel(_ channel: InputChannel, audio: XAAudio) {}
    func inputChannel(_ channel: InputChannel, roundTripMs: Double) {}
    func inputChannel(_ channel: InputChannel, clockOffsetClientMinusHost: Double) {}
    func inputChannel(_ channel: InputChannel, nowPlaying: XANowPlaying) {}
    func inputChannel(_ channel: InputChannel, failed error: PadError) {}
}
