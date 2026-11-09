import AVFoundation
import UIKit
import XADisplayProtocol
import XCTest

@testable import XADisplay

final class InjectedCoverageTests: XCTestCase {
    func testInjectedControlsGesturesAndDatagrams() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        let controller = prepared(in: window)
        controller.features.touchscreenGestures = true
        controller.features.threeFingerShortcuts = true
        controller.features.pinchMagnifier = true
        controller.features.scrollInertia = true
        controller.features.mediaRemote = true
        controller.features.rememberMacs = true
        controller.features.oneTapReconnect = true
        controller.features.gestureTuning.sidebarOnLeft = true
        controller.features.clipboardSync = true
        controller.settingsDocument.twoFingerScroll = true
        controller.settingsDocument.rightClick = "both"
        controller.assist.edgeDrawer = true
        controller.assist.windowChrome = true
        controller.assist.loupeWhileDragging = false
        controller.assist.trafficLights = true
        controller.videoSize = CGSize(width: 1920, height: 1080)
        controller.layoutVideo()

        let changed = ScriptedPan(state: .changed, translation: CGPoint(x: 24, y: -16), velocity: .zero, location: CGPoint(x: 200, y: 200))
        controller.scrollPan(changed)
        let ended = ScriptedPan(state: .ended, translation: CGPoint(x: 12, y: -40), velocity: CGPoint(x: 600, y: -400), location: CGPoint(x: 220, y: 180))
        controller.scrollPan(ended)
        let three = ScriptedPan(state: .ended, translation: CGPoint(x: -80, y: 4), velocity: .zero, location: CGPoint(x: 300, y: 300))
        controller.threePan(three)
        let pinch = ScriptedPinch(state: .changed, scale: 1.4, location: CGPoint(x: 400, y: 300))
        controller.pinched(pinch)
        controller.twoTap()
        let hold = ScriptedPress(state: .began, location: CGPoint(x: 180, y: 220))
        controller.twoHold(hold)
        let edge = ScriptedEdge(state: .ended, translation: CGPoint(x: 48, y: 0), location: CGPoint(x: 10, y: 200))
        controller.edgePan(edge)
        let drawer = ScriptedEdge(state: .ended, translation: CGPoint(x: -80, y: 0), location: CGPoint(x: 1010, y: 240))
        controller.drawerPan(drawer)

        controller.features.trackpadMode = true
        let point = XAPoint(x: 12, y: -8)
        controller.perform(.drag(.moved, point), finger: CGPoint(x: 12, y: -8), pointer: CGPoint(x: 12, y: -8), time: 3)
        controller.perform(.tap(point), finger: .zero, pointer: .zero, time: 3.2)
        controller.perform(.longPress(point), finger: .zero, pointer: .zero, time: 3.4)
        controller.features.trackpadMode = false

        controller.windowFrames = [XARect(x: 0.05, y: 0.05, width: 0.7, height: 0.7)]
        let frames = controller.windowViewFrames()
        XCTAssertFalse(frames.isEmpty)
        if let frame = frames.first {
            let start = XAPoint(x: frame.minX + 30, y: frame.minY + 4)
            controller.dragOriginView = start
            controller.dragOriginTime = 4
            let finger = CGPoint(x: start.x - 180, y: start.y + 2)
            controller.perform(.drag(.ended, XAPoint(x: Double(finger.x), y: Double(finger.y))), finger: finger, pointer: finger, time: 4.04)
            let corner = CGPoint(x: frame.minX, y: frame.minY)
            if let hit = controller.resizeHit(at: corner) {
                controller.resizing = hit
                controller.resizeOrigin = XAPoint(x: Double(corner.x), y: Double(corner.y))
                let moved = CGPoint(x: corner.x + 24, y: corner.y + 16)
                controller.perform(.drag(.moved, XAPoint(x: Double(moved.x), y: Double(moved.y))), finger: moved, pointer: moved, time: 5)
                controller.perform(.drag(.ended, XAPoint(x: Double(moved.x), y: Double(moved.y))), finger: moved, pointer: moved, time: 5.1)
            }
        }
        controller.showLoupe(at: CGPoint(x: 120, y: 160))
        controller.magnifier.pinch(by: 1.6, around: XAPoint(x: 0.4, y: 0.4))
        controller.applyMagnifier()
        controller.noteOrientation("portrait")
        controller.orientTimer?.invalidate()
        controller.directory.remember(SavedMac(id: "office", name: "Office", token: "ABCD2345", lastUsed: 10))
        controller.applyLaunchRoute()
        controller.macBrowser.stop()
        release(controller)
    }

    func testPickerMediaDatagramsAndInput() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        let controller = prepared(in: window)
        var assist = TouchAssist()
        assist.trafficLights = true
        assist.windowChrome = true
        controller.chrome.layout(windows: [CGRect(x: 40, y: 40, width: 520, height: 320)], assist: assist)
        controller.chrome.showMenus(["File", "Edit"], large: true)
        sendTouches(in: controller.view)
        controller.chrome.setDrawer(open: true)
        sendTouches(in: controller.view)

        let picker = MacPickerViewController(style: .grouped)
        picker.loadViewIfNeeded()
        picker.discovered = ["Office"]
        picker.saved = [SavedMac(id: "office", name: "Office", token: "ABCD2345", lastUsed: 10)]
        var picks = 0
        picker.onSelectDiscovered = { _ in picks += 1 }
        picker.onSelectSaved = { _ in picks += 1 }
        _ = picker.numberOfSections(in: picker.tableView)
        for section in 0..<2 {
            _ = picker.tableView(picker.tableView, titleForHeaderInSection: section)
            _ = picker.tableView(picker.tableView, titleForFooterInSection: section)
            let rows = picker.tableView(picker.tableView, numberOfRowsInSection: section)
            for row in 0..<rows {
                let path = IndexPath(row: row, section: section)
                _ = picker.tableView(picker.tableView, cellForRowAt: path)
                picker.tableView(picker.tableView, didSelectRowAt: path)
            }
        }
        XCTAssertEqual(picks, 2)
        picker.discovered = []
        picker.saved = []
        _ = picker.tableView(picker.tableView, cellForRowAt: IndexPath(row: 0, section: 0))
        _ = picker.tableView(picker.tableView, cellForRowAt: IndexPath(row: 0, section: 1))

        let media = MediaRemoteViewController()
        media.loadViewIfNeeded()
        media.show(XANowPlaying(session: 1, appName: "", title: "", artist: ""))
        media.show(XANowPlaying(session: 1, appName: "Music", title: "Song", artist: "Artist", position: 2, duration: 20))
        var commands = 0
        media.onCommand = { _, _ in commands += 1 }
        media.onClose = { commands += 1 }
        if let slider = findSlider(in: media.view) {
            slider.value = 0.9
        }
        sendTouches(in: media.view)
        XCTAssertGreaterThan(commands, 0)

        let browser = NetServiceBrowser()
        let service = NetService(domain: "local.", type: "_xahost._tcp.", name: "Office")
        controller.macBrowser.netServiceBrowser(browser, didFind: service, moreComing: false)
        controller.macBrowser.netServiceBrowser(browser, didFind: service, moreComing: true)
        controller.macBrowser.netServiceBrowser(browser, didRemove: service, moreComing: false)
        let packet = UDPVideoPacket(sequence: 1, frameID: 3, fragmentIndex: 0, fragmentCount: 2, keyframe: true, fec: false, payload: Data(repeating: 1, count: 16))
        controller.receiver.ingestDatagram(packet.encode())
        var sequence: UInt16 = 4
        let parts = UDPVideoPacketizer.packetize(frame: Data(repeating: 9, count: 48), frameID: 4, nextSequence: &sequence, keyframe: false)
        for part in parts { controller.receiver.ingestDatagram(part.encode()) }
        controller.receiver.ingestDatagram(Data([0, 1, 2]))

        let now = UInt64(Date().timeIntervalSince1970 * 1000)
        controller.input.queue.sync {
            controller.input.handle(.helloAck(XAHelloAck(accepted: true, session: 4, reason: "ok")))
            controller.input.handle(.pong(XAPong(session: 4, clientUnixMs: now > 20 ? now - 20 : 0, hostUnixMs: now > 10 ? now - 10 : 0)))
            controller.input.handle(.clipboard(XAClipboard(session: 4, seq: 1, revision: 9, text: "copied")))
            controller.input.handle(.nowPlaying(XANowPlaying(session: 4, appName: "Music", title: "Song")))
            controller.input.handle(.helloAck(XAHelloAck(accepted: false, session: 0, reason: "token")))
        }
        controller.clipboard.enabled = true
        controller.clipboard.checkPasteboard()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        controller.inputChannel(controller.input, failed: .decode)
        XCTAssertEqual(controller.statusLabel.text, PadError.decode.userMessage)

        controller.sidebar.setShowsMedia(true)
        sendTouches(in: controller.sidebar)
        controller.connectionOverlay.show(macs: ["Office"], code: "ABCD2345")
        sendTouches(in: controller.connectionOverlay)
        controller.healthTimer?.invalidate()
        controller.orientTimer?.invalidate()
        controller.titleTimer?.invalidate()
        controller.keepalive?.invalidate()
        controller.pillTimer?.invalidate()
        controller.clipboard.stop()
        controller.receiver.pause()
        controller.input.pause()
        controller.macBrowser.stop()
        release(controller)
    }

    private func prepared(in window: UIWindow) -> ReceiverViewController {
        let controller = ReceiverViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        controller.healthTimer?.invalidate()
        controller.healthTimer = nil
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        return controller
    }

    private func release(_ controller: ReceiverViewController) {
        controller.healthTimer?.invalidate()
        controller.orientTimer?.invalidate()
        controller.titleTimer?.invalidate()
        controller.keepalive?.invalidate()
        controller.pillTimer?.invalidate()
        controller.clipboard.stop()
        controller.receiver.pause()
        controller.input.pause()
        controller.macBrowser.stop()
        controller.userDisconnect()
    }

    private func sendTouches(in view: UIView) {
        if let button = view as? UIButton {
            button.sendActions(for: .touchUpInside)
        }
        if let slider = view as? UISlider {
            slider.sendActions(for: .touchUpInside)
        }
        for subview in view.subviews { sendTouches(in: subview) }
    }

    private func findSlider(in view: UIView) -> UISlider? {
        if let slider = view as? UISlider { return slider }
        for subview in view.subviews {
            if let slider = findSlider(in: subview) { return slider }
        }
        return nil
    }
}

private final class ScriptedPan: UIPanGestureRecognizer {
    private var scriptedState: UIGestureRecognizer.State
    private var scriptedTranslation: CGPoint
    private let scriptedVelocity: CGPoint
    private let scriptedLocation: CGPoint

    init(state: UIGestureRecognizer.State, translation: CGPoint, velocity: CGPoint, location: CGPoint) {
        scriptedState = .possible
        scriptedTranslation = translation
        scriptedVelocity = velocity
        scriptedLocation = location
        super.init(target: nil, action: nil)
        scriptedState = state
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var state: UIGestureRecognizer.State {
        get { scriptedState }
        set { scriptedState = newValue }
    }

    override func translation(in view: UIView?) -> CGPoint { scriptedTranslation }
    override func setTranslation(_ translation: CGPoint, in view: UIView?) { scriptedTranslation = translation }
    override func velocity(in view: UIView?) -> CGPoint { scriptedVelocity }
    override func location(in view: UIView?) -> CGPoint { scriptedLocation }
}

private final class ScriptedPinch: UIPinchGestureRecognizer {
    private var scriptedState: UIGestureRecognizer.State
    private let scriptedLocation: CGPoint

    init(state: UIGestureRecognizer.State, scale: CGFloat, location: CGPoint) {
        scriptedState = .possible
        scriptedLocation = location
        super.init(target: nil, action: nil)
        scriptedState = state
        self.scale = scale
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var state: UIGestureRecognizer.State {
        get { scriptedState }
        set { scriptedState = newValue }
    }

    override func location(in view: UIView?) -> CGPoint { scriptedLocation }
}

private final class ScriptedPress: UILongPressGestureRecognizer {
    private var scriptedState: UIGestureRecognizer.State
    private let scriptedLocation: CGPoint

    init(state: UIGestureRecognizer.State, location: CGPoint) {
        scriptedState = .possible
        scriptedLocation = location
        super.init(target: nil, action: nil)
        scriptedState = state
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var state: UIGestureRecognizer.State {
        get { scriptedState }
        set { scriptedState = newValue }
    }

    override func location(in view: UIView?) -> CGPoint { scriptedLocation }
}

private final class ScriptedEdge: UIScreenEdgePanGestureRecognizer {
    private var scriptedState: UIGestureRecognizer.State
    private let scriptedTranslation: CGPoint
    private let scriptedLocation: CGPoint

    init(state: UIGestureRecognizer.State, translation: CGPoint, location: CGPoint) {
        scriptedState = .possible
        scriptedTranslation = translation
        scriptedLocation = location
        super.init(target: nil, action: nil)
        scriptedState = state
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var state: UIGestureRecognizer.State {
        get { scriptedState }
        set { scriptedState = newValue }
    }

    override func translation(in view: UIView?) -> CGPoint { scriptedTranslation }
    override func location(in view: UIView?) -> CGPoint { scriptedLocation }
}
