import UIKit
import XADisplayProtocol
import XCTest

@testable import XADisplay

final class SurfaceCoverageTests: XCTestCase {
    func testReceiverGesturesRotationAndSettingsSync() {
        UserDefaults.standard.set(true, forKey: "XADisplay.didOnboard")
        let controller = ReceiverViewController()
        controller.loadViewIfNeeded()
        controller.healthTimer?.invalidate()
        controller.healthTimer = nil
        controller.orientTimer?.invalidate()
        controller.receiver.pause()
        controller.input.pause()
        controller.macBrowser.stop()
        controller.view.frame = CGRect(x: 0, y: 0, width: 768, height: 1024)
        controller.view.layoutIfNeeded()
        controller.features.commandStrip = true
        controller.features.windowSnapping = true
        controller.features.touchscreenGestures = true
        controller.features.followRotation = true
        controller.features.rotationMode = "stream"
        controller.videoSize = CGSize(width: 1440, height: 1080)
        controller.viewDidLayoutSubviews()
        controller.viewDidAppear(false)
        controller.layoutVideo()
        controller.layoutCursor()
        controller.releaseModifiers()
        controller.refreshStats()
        let point = XAPoint(x: 40, y: 80)
        let finger = CGPoint(x: 40, y: 80)
        controller.assist.loupeWhileDragging = false
        controller.assist.windowChrome = false
        controller.perform(.tap(point), finger: finger, pointer: finger, time: 2)
        controller.perform(.scroll(dx: 4, dy: -3, inertia: false), finger: finger, pointer: finger, time: 4)
        for item in CommandStripItem.standard { controller.command(item) }
        controller.sendSnap(.leftHalf)
        controller.sendSnap(.full)
        controller.sendShortcut(KeyShortcut(input: "v", modifiers: .command))
        var document = XASettingsDocument.defaults
        document.features.clipboardSync = false
        document.features.audio = false
        document.keyboardEnabled = true
        controller.apply(document: document, token: "ABCD2345", broadcast: true)
        controller.copyDiagnostics()
        controller.toggleKeyboard()
        XCTAssertEqual(controller.modifiers(from: .command).rawValue, XAModifierMask.command.rawValue)
        XCTAssertNil(controller.resizeHit(at: CGPoint(x: 8, y: 8)))
        XCTAssertTrue(controller.windowViewFrames().isEmpty)
        let placed = VideoPlacement.frame(host: controller.view.bounds, rotateClockwise: true)
        XCTAssertGreaterThan(placed.bounds.width, 0)
        XCTAssertFalse(PadError.decode.userMessage.isEmpty)
        XCTAssertFalse(PadError.pairing.userMessage.isEmpty)
        XCTAssertFalse(PadError.transport("down").userMessage.isEmpty)
        XCTAssertFalse(PadError.protocolVersion.userMessage.isEmpty)
        let receiver = controller.receiver!
        controller.videoReceiver(receiver, statusDidChange: "listening")
        controller.videoReceiver(receiver, connected: true, transport: .usb)
        controller.xaHost = true
        controller.videoReceiver(receiver, videoSizeDidChange: CGSize(width: 1440, height: 1080))
        controller.videoReceiver(receiver, cursor: CGPoint(x: 0.4, y: 0.6), visible: true)
        controller.videoReceiverBecameXAHost(receiver)
        controller.videoReceiver(receiver, stream: StreamAnnouncement(preset: "balanced", width: 1440, height: 1080, fps: 30, bitrate: 8_000_000, experimental: false))
        controller.videoReceiver(receiver, metrics: XAMetrics(captureToAckMs: 14, encodeMs: 3))
        controller.videoReceiver(receiver, windows: "[]")
        controller.videoReceiver(receiver, menus: "[]")
        controller.videoReceiver(receiver, frontBundle: "com.apple.finder")
        controller.videoReceiver(receiver, orientation: "portrait", mode: "stream", letterbox: false)
        controller.videoReceiver(receiver, orientation: "landscape", mode: "resolution", letterbox: true)
        controller.inputChannel(controller.input, armed: true, reason: "ok")
        controller.features.clipboardSync = true
        controller.inputChannel(controller.input, clipboard: "copied", revision: 2)
        controller.inputChannel(controller.input, roundTripMs: 9)
        controller.inputChannel(controller.input, clockOffsetClientMinusHost: 1)
        controller.inputChannel(controller.input, nowPlaying: XANowPlaying(session: 1, appName: "Music", title: "Song"))
        let packet = XAAudio(session: 1, sampleRate: 48_000, channels: 2, pcm: Data([0, 1, 2, 3]))
        controller.inputChannel(controller.input, audio: packet)
    }

    func testSettingsMediaBatteryAndChromeViews() {
        let settings = SettingsViewController(document: .defaults, token: "ABCD2345")
        settings.loadViewIfNeeded()
        let sections = settings.numberOfSections(in: settings.tableView)
        XCTAssertGreaterThan(sections, 0)
        for section in 0..<sections {
            _ = settings.tableView(settings.tableView, titleForHeaderInSection: section)
            _ = settings.tableView(settings.tableView, titleForFooterInSection: section)
            let rows = settings.tableView(settings.tableView, numberOfRowsInSection: section)
            for row in 0..<rows {
                let path = IndexPath(row: row, section: section)
                _ = settings.tableView(settings.tableView, heightForRowAt: path)
                _ = settings.tableView(settings.tableView, cellForRowAt: path)
            }
        }
        let media = MediaRemoteViewController()
        media.loadViewIfNeeded()
        media.show(XANowPlaying(session: 1, appName: "Music", title: "Song", artist: "Artist", position: 1, duration: 20))
        let sidebar = SidebarView(frame: CGRect(x: 0, y: 0, width: 168, height: 900))
        sidebar.layoutIfNeeded()
        let strip = CommandStripView(frame: CGRect(x: 0, y: 0, width: 768, height: 52))
        strip.layoutIfNeeded()
        let stats = StatsOverlay(frame: CGRect(x: 0, y: 0, width: 200, height: 24))
        stats.text = "30 fps"
        XCTAssertEqual(stats.text, "30 fps")
    }
}
