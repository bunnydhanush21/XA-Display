@preconcurrency import AppKit
@preconcurrency import Darwin
import XADisplayProtocol
import XCTest

@testable import XADisplayHost

@MainActor
final class HostLogicTests: XCTestCase {
    func testSettingsOrientationDiagnosticsAndVideoControl() {
        let host = HostController()
        host.setRequirePairing(false)
        host.setClipboard(true)
        host.setWindowSnapping(true)
        host.setTouchGestures(true)
        host.setWiFi(true)
        host.setOneTapReconnect(true)
        host.setRememberMacs(true)
        host.setMediaRemote(true)
        host.setAutoConnect(false)
        host.setLowLatencyWiFi(true)
        host.setSavedPresets(true)
        host.saveNamedPreset("Desk")
        host.setUserPaused(true)
        host.setUserPaused(false)
        host.regenerateToken()
        let token = host.currentToken()
        XCTAssertFalse(host.diagnostics().contains(token))
        var document = host.settingsDocument()
        document.features.followRotation = false
        document.features.orientationLock = "landscape"
        document.features.rotationMode = "resolution"
        document.features.custom.enabled = true
        document.features.custom.width = 1280
        document.features.custom.height = 800
        document.preset = "safe"
        host.applySharedSettings(SettingsSync.encode(document), broadcast: true)
        host.applyLocalDocument(document, broadcast: false)
        host.applyOrientation(requested: "portrait", mode: "stream")
        host.applyOrientation(requested: "landscape", mode: "resolution")
        let hello = LegacyHello(pixelsWide: 1440, pixelsHigh: 1080, scale: 2, device: "iPad", id: "pad", orientation: "landscape")
        host.handleVideo(VideoControlMessage.hello(hello).jsonData() ?? Data())
        host.handleVideo(VideoControlMessage.xaAuth(id: "pad", proof: ChannelAuth.proof(token: token, channel: .video, nonce: "pad")).jsonData() ?? Data())
        host.handleVideo(VideoControlMessage.xaOrient(orientation: "portrait", mode: "resolution", letterbox: false).jsonData() ?? Data())
        host.handleVideo(VideoControlMessage.frameAck(FrameAck(seq: 1, captureMs: 10, receiveMs: 12, enqueueMs: 13)).jsonData() ?? Data())
        let health = HealthReport(thermal: .nominal, batteryFraction: 0.8, batteryState: "unplugged", fpsDelivered: 30, decodeFails: 0)
        host.handleVideo(VideoControlMessage.health(health).jsonData() ?? Data())
        host.handleVideo(VideoControlMessage.decodeFailed(preset: "native").jsonData() ?? Data())
        host.handleVideo(VideoControlMessage.xaBattery(text: "80%", heat: false).jsonData() ?? Data())
        host.handleVideo(VideoControlMessage.xaSettings(SettingsSync.encode(document)).jsonData() ?? Data())
        host.handleVideo(VideoControlMessage.xaNack("1,2").jsonData() ?? Data())
        host.handleVideo(VideoControlMessage.touch(phase: "moved", x: 0.2, y: 0.3).jsonData() ?? Data())
        host.ingestVideo(Data(repeating: 0xFF, count: 32))
        host.ingestInput(Data(repeating: 0xFF, count: 32))
        let menu = host.menuSnapshot()
        XCTAssertFalse(menu.preset.isEmpty)
        XCTAssertEqual(host.batterySummary().isEmpty, false)
        host.log(HostError.pairing)
        host.log(HostError.permission("screen"))
        host.log(HostError.codec("capture"))
        host.log(HostError.transport("reset"))
        host.log(HostError.virtualDisplay)
    }

    func testWindowChromeAudioRouteAndVideoSend() {
        let host = HostController()
        host.setRequirePairing(false)
        host.setTouchGestures(true)
        host.lastDisplayFrame = XARect(x: 0, y: 0, width: 1440, height: 1080)
        let actions: [WindowAction] = [.snapLeft, .snapRight, .fill, .moveToMain, .fillToggle, .tileTopLeft, .pressClose, .missionControl, .notificationCenter, .saveLayout]
        for action in actions { host.applyWindow(action) }
        host.applyChrome(op: ChromeOp.menu.rawValue, index: 0, windowIndex: 0, dx: 0, dy: 0)
        host.applyChrome(op: ChromeOp.resize.rawValue, index: UInt16(ResizeCorner.bottomRight.rawValue), windowIndex: 0, dx: 0.1, dy: 0.1)
        host.postShortcut(KeyShortcut(input: "c", modifiers: .command))
        host.publishChrome()
        host.publishNowPlaying()
        host.toggleAudioBundle("com.apple.finder")
        host.toggleAudioBundle("com.apple.finder")
        host.setAudioMode(.selected)
        host.setAudio(false)
        host.transport = .wifi
        host.setLowLatencyWiFi(true)
        host.sendVideo(Data([0, 0, 0, 1, 0x65]), keyframe: true, captureMs: 5, encodeMs: 1)
        host.sendVideo(Data([0, 0, 0, 1, 0x41]), keyframe: false, captureMs: 6, encodeMs: 1)
        host.tuneWiFi(rttMs: 40)
        host.tuneWiFi(rttMs: 180)
        _ = host.audioMenuState()
        host.releaseInput(.transport("The input link closed."))
        host.settings.legacyTokenSeal = true
        host.installOutboundSeal(ChannelSeal(token: "ABCD2345", direction: .hostToPad))
        host.publishVideoLink()
        host.setLowLatencyWiFi(false)
        host.sendVideo(Data([0, 0, 0, 1, 0x65]), keyframe: true, captureMs: 5, encodeMs: 1)
        host.flushVideoOutbound()
        host.setLowLatencyWiFi(true)
        host.sendVideo(Data([0, 0, 0, 1, 0x41]), keyframe: false, captureMs: 6, encodeMs: 1)
        host.flushVideoOutbound()
        var descriptors = [Int32](repeating: 0, count: 2)
        if Darwin.pipe(&descriptors) == 0 {
            host.videoOut.note(fd: descriptors[1], connection: nil, sender: host.udpSender)
            host.flushVideoOutbound()
            host.setLowLatencyWiFi(false)
            host.sendVideo(Data([0, 0, 0, 1, 0x65, 0x10]), keyframe: true, captureMs: 7, encodeMs: 1)
            host.flushVideoOutbound()
            close(descriptors[0])
            close(descriptors[1])
        }
        var seal = ChannelSeal(token: host.currentToken(), direction: .padToHost)
        let hello = VideoControlMessage.xaHello.jsonData() ?? Data()
        if let sealed = seal.seal(hello, aad: SealChannel.video.aad) {
            host.ingestVideo(LengthPrefixedFraming.encode(sealed))
        }
        host.inboundSeal = SealInbox(token: "ABCD2345")
        var ackSeal = ChannelSeal(token: "ABCD2345", direction: .padToHost)
        for seq in [UInt64(1), UInt64(2)] {
            let ack = VideoControlMessage.frameAck(FrameAck(seq: seq, captureMs: 5, receiveMs: 6, enqueueMs: 7))
            if let sealed = ackSeal.seal(ack.jsonData() ?? Data(), aad: SealChannel.video.aad) {
                host.ingestVideo(LengthPrefixedFraming.encode(sealed))
            }
        }
        XCTAssertTrue(HostError.wakeUnavailable.userMessage.contains("wake"))
        XCTAssertTrue(HostError.seal.userMessage.contains("seal"))
        XCTAssertTrue(HostError.audio("route").userMessage.contains("Audio"))
        XCTAssertTrue(HostError.captureStopped("ended").userMessage.contains("Capture"))
        host.stop()
    }

    func testHandshakeInstallsSessionKeysBeforeHello() {
        let host = HostController()
        host.settings.legacyTokenSeal = false
        guard let client = SessionHandshake.clientOffer() else { return XCTFail("offer") }
        let reply = host.acceptHandshake(client.frame)
        XCTAssertNotNil(reply)
        XCTAssertFalse(host.sessionReady)
        guard let reply = reply, let finished = SessionHandshake.clientFinish(token: host.currentToken(), state: client.state, reply: reply) else {
            return XCTFail("finish")
        }
        XCTAssertNil(host.acceptHandshake(finished.finish))
        XCTAssertTrue(host.sessionReady)
        XCTAssertNil(host.acceptHandshake(client.frame))
    }
}
