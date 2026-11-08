import AVFoundation
import UIKit
import XADisplayProtocol
import XCTest

@testable import XADisplay

final class ComponentCoverageTests: XCTestCase {
    func testChromeClipboardBatteryParseAndSeal() {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 768, height: 1024))
        let chrome = TouchChromeController()
        chrome.install(in: host)
        chrome.setLarge(true)
        chrome.setDrawer(open: true)
        chrome.toggleDrawer()
        chrome.layout(windows: [CGRect(x: 20, y: 20, width: 420, height: 280)], assist: TouchAssist())
        chrome.showMenus(["File", "Edit", "View"], large: true)
        chrome.setDrawer(open: false)
        let sidebar = SidebarView(frame: CGRect(x: 0, y: 0, width: 168, height: 900))
        sidebar.setModifier(.command, on: true)
        sidebar.setCollapsed(true)
        sidebar.setShowsMedia(true)
        sidebar.setLarge(true)
        let keys = KeyInputView(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
        var typed = ""
        keys.onText = { typed = $0 }
        keys.onDelete = { typed = "" }
        keys.insertText("ab")
        keys.deleteBackward()
        XCTAssertEqual(typed, "")
        let board = ClipboardBridge()
        board.enabled = true
        board.applyRemote(text: "from-mac", revision: 4)
        board.start()
        board.stop()
        let parsed = BatteryRegistry.parse([
            "CurrentCapacity": NSNumber(value: 80),
            "MaxCapacity": 100.0,
            "Temperature": 3100,
            "IsCharging": 1,
            "ExternalConnected": 0,
            "InstantAmperage": NSNumber(value: -400),
            "Voltage": 4100,
            "CycleCount": 12,
            "DesignCapacity": 100
        ])
        XCTAssertEqual(parsed.currentCapacity ?? 0, 80, accuracy: 0.1)
        XCTAssertEqual(parsed.isCharging, true)
        _ = AACLCDecoder().decode(cookie: Data([1, 2, 3]), frame: Data([4, 5, 6, 7]))
        let receiver = VideoReceiver(displayLayer: AVSampleBufferDisplayLayer())
        receiver.setPairingToken("ABCD2345")
        var seal = ChannelSeal(token: "ABCD2345")
        let json = VideoControlMessage.ping(t: 3).jsonData() ?? Data()
        let sealed = seal.seal(json, aad: SealChannel.video.aad) ?? Data()
        XCTAssertEqual(receiver.openSealed(sealed, channel: .video), json)
        XCTAssertNil(receiver.openSealed(Data([0, 1]), channel: .udp))
        XCTAssertFalse(PadError.seal.userMessage.isEmpty)
        XCTAssertFalse(PadError.malformed.userMessage.isEmpty)
        board.checkPasteboard()
        let loop = BatteryCareLoop()
        _ = loop.tick(enabledTelemetry: true, chargeLimit: false, config: ChargeLimitConfig())
        _ = loop.tick(enabledTelemetry: false, chargeLimit: true, config: ChargeLimitConfig())
        loop.restore()
    }

    func testMoreGesturesOnAPausedReceiver() {
        let controller = ReceiverViewController()
        controller.loadViewIfNeeded()
        controller.healthTimer?.invalidate()
        controller.receiver.pause()
        controller.input.pause()
        controller.macBrowser.stop()
        controller.view.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
        controller.view.layoutIfNeeded()
        controller.assist.loupeWhileDragging = false
        controller.assist.windowChrome = false
        controller.features.touchscreenGestures = true
        let point = XAPoint(x: 30, y: 40)
        let finger = CGPoint(x: 30, y: 40)
        controller.perform(.doubleTap(point), finger: finger, pointer: finger, time: 1)
        controller.perform(.longPress(point), finger: finger, pointer: finger, time: 2)
        controller.perform(.twoFingerTap(point), finger: finger, pointer: finger, time: 3)
        controller.perform(.drag(.began, point), finger: finger, pointer: finger, time: 4)
        controller.perform(.drag(.moved, point), finger: finger, pointer: finger, time: 4.1)
        controller.perform(.drag(.ended, point), finger: finger, pointer: finger, time: 4.2)
        controller.perform(.relativeClick(.right), finger: finger, pointer: finger, time: 5)
        _ = controller.normalize(point)
        _ = controller.contentSize()
        controller.videoSize = CGSize(width: 1920, height: 1080)
        controller.layoutVideo()
    }
}
