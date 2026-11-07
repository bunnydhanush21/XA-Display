import XCTest
@testable import XADisplayProtocol

final class TouchChromeTests: XCTestCase {
    func testContentDoubleTapIsNotAWindowAction() {
        let window = XARect(x: 0, y: 0, width: 400, height: 300)
        let body = XAPoint(x: 200, y: 80)
        XCTAssertTrue(WindowChrome.isContent(point: body, window: window))
        XCTAssertFalse(WindowChrome.isTitleBar(body, window: window))
        XCTAssertTrue(WindowChrome.isTitleBar(XAPoint(x: 40, y: 10), window: window))
        var arbiter = TitleBarArbiter(window: 0.35)
        XCTAssertEqual(arbiter.tap(point: body, time: 1, windows: [window]), .click(body))
        XCTAssertEqual(arbiter.tap(point: XAPoint(x: 30, y: 8), time: 2, windows: [window]), .pending)
        XCTAssertEqual(arbiter.tap(point: XAPoint(x: 36, y: 12), time: 2.2, windows: [window]), .fillToggle(window))
        XCTAssertEqual(arbiter.tap(point: XAPoint(x: 30, y: 8), time: 3, windows: [window]), .pending)
        XCTAssertEqual(arbiter.flush(now: 3.4), .click(XAPoint(x: 30, y: 8)))
    }

    func testTitleFlickAndQuartersIgnoreContentDrags() {
        let window = XARect(x: 10, y: 10, width: 300, height: 200)
        XCTAssertNil(TitleBarFlick.region(start: XAPoint(x: 80, y: 90), dx: -80, dy: 0, speed: 900, windows: [window]))
        XCTAssertEqual(TitleBarFlick.region(start: XAPoint(x: 80, y: 16), dx: -90, dy: 4, speed: 900, windows: [window]), .leftHalf)
        XCTAssertEqual(TitleBarFlick.region(start: XAPoint(x: 80, y: 16), dx: 40, dy: 80, speed: 900, windows: [window]), .bottomRight)
        let display = XARect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertEqual(QuarterFrame.frame(.topLeft, display: display).height, 400, accuracy: 0.1)
    }

    func testFillRestoreAndResizeHandles() {
        let display = XARect(x: 0, y: 0, width: 800, height: 600)
        let small = XARect(x: 40, y: 40, width: 200, height: 150)
        let filled = FillToggle.toggle(window: small, display: display, saved: nil)
        XCTAssertEqual(filled.frame, display)
        XCTAssertEqual(filled.saved, small)
        let restored = FillToggle.toggle(window: display, display: display, saved: filled.saved)
        XCTAssertEqual(restored.frame, small)
        XCTAssertNil(restored.saved)
        XCTAssertEqual(WindowChrome.resizeCorner(point: XAPoint(x: 4, y: 4), window: small), .topLeft)
        XCTAssertNil(WindowChrome.resizeCorner(point: XAPoint(x: 100, y: 100), window: small))
        let grown = WindowResize.resized(window: small, corner: .bottomRight, translation: XAPoint(x: 20, y: 10))
        XCTAssertEqual(grown.width, 220, accuracy: 0.1)
        let lights = TrafficLights.targets(titleBar: WindowChrome.titleBar(of: small))
        XCTAssertEqual(lights.count, 3)
        XCTAssertGreaterThanOrEqual(lights[0].rect.width, 36)
    }

    func testEdgeDrawerZoomRepeatAndMomentum() {
        XCTAssertTrue(EdgeDrawerGate.shouldOpen(startX: 990, viewWidth: 1000, translationX: -50))
        XCTAssertFalse(EdgeDrawerGate.shouldOpen(startX: 12, viewWidth: 1000, translationX: 40))
        XCTAssertEqual(EdgeSystemAction.missionControl.shortcut.input, "UIKeyInputUpArrow")
        let custom = AppZoomBinding(bundleID: "com.apple.Safari", zoomIn: "=", zoomOut: "-", modifiers: XAModifierMask.command.rawValue)
        XCTAssertEqual(ZoomProfiles.resolve(bundleID: "com.apple.Safari", bindings: [custom, .universal]).bundleID, "com.apple.Safari")
        XCTAssertEqual(ZoomProfiles.resolve(bundleID: "com.other", bindings: [custom, .universal]).bundleID, "*")
        XCTAssertFalse(RepeatGate.allow(now: 1.1, last: 1.0, interval: 0.28))
        XCTAssertTrue(RepeatGate.allow(now: 1.4, last: 1.0, interval: 0.28))
        XCTAssertGreaterThanOrEqual(TouchMetrics.target(requested: 20, large: false), 36)
        let steps = MacTouchScroll.steps(velocityX: 40, velocityY: -20)
        XCTAssertFalse(steps.contains { $0.dx < 0 || $0.dy > 0 })
        if steps.count > 1 {
            XCTAssertLessThan(abs(steps.last!.dx) + abs(steps.last!.dy), abs(steps.first!.dx) + abs(steps.first!.dy))
        }
        let nudged = CursorNudge.apply(point: XAPoint(x: 10, y: 10), offset: XAPoint(x: 2, y: -3))
        XCTAssertEqual(nudged.x, 12, accuracy: 0.01)
        XCTAssertEqual(nudged.y, 7, accuracy: 0.01)
        let assist = TouchAssist()
        XCTAssertEqual(EdgeRouter.route(assist.binding(for: .notificationCenter)), .accessibility)
        if case .key(let shortcut) = EdgeRouter.route(assist.binding(for: .missionControl)) {
            XCTAssertEqual(shortcut.input, "UIKeyInputUpArrow")
            XCTAssertEqual(shortcut.modifiers, .control)
        } else {
            XCTFail("Mission Control should be a key")
        }
        let display = XARect(x: 100, y: 50, width: 200, height: 100)
        let encoded = ChromeWire.windows([ChromeWire.normalized(XARect(x: 100, y: 50, width: 100, height: 50), in: display)])
        let parsed = ChromeWire.parseWindows(encoded)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].width, 0.5, accuracy: 0.001)
        XCTAssertEqual(ChromeWire.parseMenus(ChromeWire.menus(["File · New", "Edit · Copy"])), ["File · New", "Edit · Copy"])
        let chrome = XAInputMessage.chrome(XAChromeCommand(session: 3, seq: 4, op: .resize, index: 4, windowIndex: 1, dx: 0.1, dy: -0.2))
        XCTAssertEqual(try XAInputMessage.decode(try chrome.encode()), chrome)
        let wire = VideoControlMessage.xaWindows(encoded)
        let parsedWire = VideoControlMessage.parse(wire.jsonData() ?? Data())
        XCTAssertEqual(parsedWire, .xaWindows(encoded))
    }

    func testMouseDownWaitsUntilTheGestureIsKnown() {
        var interpreter = DirectTouchInterpreter()
        let normalize: (XAPoint) -> XAPoint? = { $0 }
        XCTAssertEqual(interpreter.feed(TouchSample(time: 0, phase: .began, location: XAPoint(x: 4, y: 4), activeTouches: 1), normalize: normalize), [])
        XCTAssertEqual(interpreter.feed(TouchSample(time: 0.05, phase: .moved, location: XAPoint(x: 6, y: 5), activeTouches: 1), normalize: normalize), [])
        XCTAssertEqual(interpreter.feed(TouchSample(time: 0.08, phase: .cancelled, location: XAPoint(x: 6, y: 5), activeTouches: 1), normalize: normalize), [])
    }
}
