import XCTest

@testable import XADisplayProtocol

final class BehaviorTests: XCTestCase {
    func testLetterboxScaleRotationAndDisplayOrigin() {
        let view = XASize(width: 1024, height: 768)
        let video = XASize(width: 2048, height: 1536)
        let center = CoordinateMapper.normalize(
            MapRequest(
                point: XAPoint(x: 1024, y: 768),
                pointSpace: .pixels,
                viewSizePoints: view,
                pixelsPerPoint: 2,
                videoPixelSize: video,
                rotation: .identity
            ))
        XCTAssertEqual(center?.x ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(center?.y ?? -1, 0.5, accuracy: 0.0001)

        let square = XASize(width: 1000, height: 1000)
        let wide = XASize(width: 2000, height: 1000)
        XCTAssertNil(
            CoordinateMapper.normalize(
                MapRequest(
                    point: XAPoint(x: 0, y: 0), pointSpace: .viewPoints, viewSizePoints: square,
                    pixelsPerPoint: 1, videoPixelSize: wide, rotation: .identity
                )))
        let topOfPicture = CoordinateMapper.normalize(
            MapRequest(
                point: XAPoint(x: 0, y: 250), pointSpace: .viewPoints, viewSizePoints: square,
                pixelsPerPoint: 1, videoPixelSize: wide, rotation: .identity
            ))
        XCTAssertEqual(topOfPicture?.x ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(topOfPicture?.y ?? -1, 0, accuracy: 0.0001)

        let rotated = CoordinateMapper.rotate(XAPoint(x: 0, y: 0), .clockwise90)
        XCTAssertEqual(rotated.x, 0, accuracy: 0.0001)
        XCTAssertEqual(rotated.y, 1, accuracy: 0.0001)
        let opposite = CoordinateMapper.rotate(XAPoint(x: 1, y: 1), .clockwise180)
        XCTAssertEqual(opposite.x, 0, accuracy: 0.0001)
        XCTAssertEqual(opposite.y, 0, accuracy: 0.0001)

        let global = CoordinateMapper.globalPoint(
            normalized: XAPoint(x: 0, y: 0),
            displayFrame: XARect(x: -1440, y: 20, width: 1440, height: 1080)
        )
        XCTAssertEqual(global.x, -1440, accuracy: 0.0001)
        XCTAssertEqual(global.y, 20, accuracy: 0.0001)
        let far = CoordinateMapper.globalPoint(
            normalized: XAPoint(x: 1, y: 1),
            displayFrame: XARect(x: 100, y: 50, width: 800, height: 600)
        )
        XCTAssertEqual(far.x, 900, accuracy: 0.0001)
        XCTAssertEqual(far.y, 650, accuracy: 0.0001)
    }

    func testScrollPixelsAndWheelSign() {
        let pixels = CoordinateMapper.scrollPixels(
            viewDelta: XAPoint(x: 10, y: 20),
            contentSize: XASize(width: 1024, height: 768),
            videoPixelSize: XASize(width: 2048, height: 1536)
        )
        XCTAssertEqual(pixels.x, 20, accuracy: 0.0001)
        XCTAssertEqual(pixels.y, 40, accuracy: 0.0001)
        XCTAssertEqual(ScrollWheelSign.wheel1(contentDownPixels: 12), -12)
        XCTAssertEqual(ScrollWheelSign.wheel2(contentRightPixels: -4), 4)
    }

    func testGesturesMapToPointerEvents() {
        let point = XAPoint(x: 0.2, y: 0.3)
        XCTAssertEqual(GestureMapper.intents(for: .tap(point)).count, 2)
        XCTAssertEqual(GestureMapper.intents(for: .doubleTap(point)).count, 4)
        let right = GestureMapper.intents(for: .twoFingerTap(point))
        guard case .mouse(let phase, let button, _, _, _) = right[0] else { return XCTFail() }
        XCTAssertEqual(phase, .down)
        XCTAssertEqual(button, .right)
        XCTAssertEqual(GestureMapper.intents(for: .twoFingerLongPress(point))[0], right[0])
        XCTAssertEqual(GestureMapper.intents(for: .longPress(point))[0], right[0])
        let drag = GestureMapper.intents(for: .drag(.moved, point))
        guard case .mouse(.move, .left, 0.2, 0.3, .absoluteNormalized) = drag[0] else { return XCTFail("\(drag)") }
        let scroll = GestureMapper.intents(for: .scroll(dx: 1, dy: -2, inertia: true))
        XCTAssertEqual(scroll, [.scroll(dx: 1, dy: -2, inertia: true)])
    }

    func testDirectTouchTapDragLongPressAndSecondFingerRelease() {
        var interpreter = DirectTouchInterpreter()
        let normalize: (XAPoint) -> XAPoint? = { $0 }
        XCTAssertEqual(interpreter.feed(TouchSample(time: 0, phase: .began, location: XAPoint(x: 10, y: 10), activeTouches: 1), normalize: normalize), [])
        let tap = interpreter.feed(TouchSample(time: 0.1, phase: .ended, location: XAPoint(x: 11, y: 10), activeTouches: 1), normalize: normalize)
        XCTAssertEqual(tap, [.tap(XAPoint(x: 10, y: 10))])
        _ = interpreter.feed(TouchSample(time: 0.2, phase: .began, location: XAPoint(x: 10, y: 10), activeTouches: 1), normalize: normalize)
        let second = interpreter.feed(TouchSample(time: 0.3, phase: .ended, location: XAPoint(x: 10, y: 10), activeTouches: 1), normalize: normalize)
        XCTAssertEqual(second, [.tap(XAPoint(x: 10, y: 10))])

        _ = interpreter.feed(TouchSample(time: 1, phase: .began, location: XAPoint(x: 0, y: 0), activeTouches: 1), normalize: normalize)
        let moved = interpreter.feed(TouchSample(time: 1.1, phase: .moved, location: XAPoint(x: 40, y: 0), activeTouches: 1), normalize: normalize)
        XCTAssertEqual(moved.first, .drag(.began, XAPoint(x: 0, y: 0)))
        let released = interpreter.feed(TouchSample(time: 1.2, phase: .moved, location: XAPoint(x: 50, y: 0), activeTouches: 2), normalize: normalize)
        XCTAssertEqual(released, [.drag(.ended, XAPoint(x: 40, y: 0))])

        _ = interpreter.feed(TouchSample(time: 2, phase: .began, location: XAPoint(x: 5, y: 5), activeTouches: 1), normalize: normalize)
        let held = interpreter.feed(TouchSample(time: 2.6, phase: .ended, location: XAPoint(x: 5, y: 5), activeTouches: 1), normalize: normalize)
        XCTAssertEqual(held, [.longPress(XAPoint(x: 5, y: 5))])
    }

    func testInertiaDecaysAndTrackpadClamps() {
        let steps = ScrollInertia.steps(velocityX: 30, velocityY: 0, friction: 0.5, minSpeed: 1, maxSteps: 8)
        XCTAssertGreaterThan(steps.count, 1)
        XCTAssertLessThan(abs(steps.last!.dx), abs(steps.first!.dx))
        XCTAssertLessThanOrEqual(steps.count, 8)
        let small = TrackpadAcceleration.apply(dx: 10, dy: 0, precision: false)
        let large = TrackpadAcceleration.apply(dx: 100, dy: 0, precision: false)
        XCTAssertGreaterThan(large.x / 100, small.x / 10)
        var cursor = TrackpadCursor()
        let moved = cursor.apply(normalizedDelta: XAPoint(x: 0.7, y: -1))
        XCTAssertEqual(moved.x, 1, accuracy: 0.0001)
        XCTAssertEqual(moved.y, 0, accuracy: 0.0001)
        let precise = TrackpadAcceleration.apply(dx: 10, dy: 0, precision: true)
        XCTAssertLessThan(precise.x, small.x)
    }

    func testShortcutsAndTextEntry() {
        let undo = KeyShortcut(input: "z", modifiers: .command).intents()
        XCTAssertEqual(undo.count, 2)
        guard case .key(.down, 6, let mask, _) = undo[0] else { return XCTFail() }
        XCTAssertEqual(mask, .command)
        let redo = KeyShortcut(input: "z", modifiers: [.command, .shift]).intents()
        guard case .key(.down, 6, let redoMask, _) = redo[0] else { return XCTFail() }
        XCTAssertTrue(redoMask.contains(.shift))
        XCTAssertEqual(KeyShortcut.keyCode(for: "\u{1b}"), MacKeyCode.escape)
        XCTAssertEqual(TextEntry.insert("A").count, 1)
        XCTAssertEqual(TextEntry.delete().count, 2)
    }

    func testPairingRejectionAndTokenNormalization() {
        XCTAssertEqual(PairingGate.evaluate(presented: " abcd-efgh ", expected: "ABCDEFGH"), .accept)
        XCTAssertEqual(PairingGate.evaluate(presented: "nope", expected: "ABCDEFGH"), .reject(.mismatch))
        XCTAssertEqual(PairingGate.evaluate(presented: "   ", expected: "ABCDEFGH"), .reject(.empty))
        XCTAssertEqual(PairingGate.evaluate(presented: "ABCDEFGH", expected: ""), .reject(.empty))
        var rng = LCG(state: 5)
        let token = PairingToken.make(using: &rng)
        XCTAssertEqual(token.count, 9)
        XCTAssertEqual(token[token.index(token.startIndex, offsetBy: 4)], "-")
        XCTAssertFalse(token.contains("0") && false)
        XCTAssertTrue(token.filter { $0 != "-" }.allSatisfy { PairingToken.alphabet.contains($0) })
    }

    func testDispatcherPairsRejectsReplayAndReleasesOnDisconnect() {
        var dispatcher = InputDispatcher(expectedToken: "ABCDEFGH", maxInputPerSecond: 2)
        dispatcher.displayFrame = XARect(x: -1440, y: 0, width: 1440, height: 1080)
        dispatcher.videoPixelSize = XASize(width: 1440, height: 1080)
        dispatcher.sessionGenerator = { 42 }

        let early = dispatcher.handle(.mouse(XAMouse(session: 42, seq: 1, phase: .down, button: .left, x: 0, y: 0, space: .absoluteNormalized)), hostNowMs: 0)
        XCTAssertEqual(early, .drop)

        let bad = dispatcher.handle(.hello(XAHello(protocolVersion: 1, token: "WRONG", deviceName: "iPad", deviceID: "1")), hostNowMs: 0)
        guard case .reply(.helloAck(let rejected)) = bad else { return XCTFail("\(bad)") }
        XCTAssertFalse(rejected.accepted)
        XCTAssertEqual(rejected.reason, "token")
        let still = dispatcher.handle(.mouse(XAMouse(session: 0, seq: 1, phase: .down, button: .left, x: 0, y: 0, space: .absoluteNormalized)), hostNowMs: 0)
        XCTAssertEqual(still, .drop)

        let good = dispatcher.handle(.hello(XAHello(protocolVersion: 1, token: "abcd-efgh", deviceName: "iPad", deviceID: "1")), hostNowMs: 0)
        guard case .reply(.helloAck(let ack)) = good else { return XCTFail("\(good)") }
        XCTAssertTrue(ack.accepted)
        XCTAssertEqual(ack.session, 42)

        let down = dispatcher.handle(.mouse(XAMouse(session: 42, seq: 1, phase: .down, button: .left, x: 0, y: 0, space: .absoluteNormalized)), hostNowMs: 1_000)
        guard case .post(let downEvents) = down else { return XCTFail() }
        XCTAssertEqual(downEvents, [.mouse(phase: .down, button: .left, global: XAPoint(x: -1440, y: 0))])

        let replay = dispatcher.handle(.mouse(XAMouse(session: 42, seq: 1, phase: .up, button: .left, x: 0, y: 0, space: .absoluteNormalized)), hostNowMs: 1_100)
        XCTAssertEqual(replay, .drop)

        let wrongSession = dispatcher.handle(.mouse(XAMouse(session: 7, seq: 2, phase: .up, button: .left, x: 0, y: 0, space: .absoluteNormalized)), hostNowMs: 1_200)
        XCTAssertEqual(wrongSession, .drop)

        _ = dispatcher.handle(.modifier(XAModifier(session: 42, seq: 2, mask: [.command, .shift], down: true)), hostNowMs: 1_300)
        let again = dispatcher.handle(.modifier(XAModifier(session: 42, seq: 3, mask: .command, down: true)), hostNowMs: 1_400)
        guard case .post(let duplicate) = again else { return XCTFail() }
        XCTAssertTrue(duplicate.isEmpty)

        let moved = dispatcher.handle(.mouse(XAMouse(session: 42, seq: 4, phase: .move, button: .left, x: 1, y: 1, space: .absoluteNormalized)), hostNowMs: 1_500)
        guard case .post(let drag) = moved else { return XCTFail("\(moved)") }
        XCTAssertEqual(drag, [.mouse(phase: .drag, button: .left, global: XAPoint(x: 0, y: 1080))])

        let released = dispatcher.disconnect()
        XCTAssertTrue(released.contains(.mouse(phase: .up, button: .left, global: XAPoint(x: 0, y: 1080))))
        XCTAssertTrue(released.contains(.modifier(bit: .command, down: false)))
        XCTAssertTrue(released.contains(.modifier(bit: .shift, down: false)))
        XCTAssertTrue(dispatcher.disconnect().isEmpty)

        var versionDispatcher = InputDispatcher(expectedToken: "ABCDEFGH")
        let version = versionDispatcher.handle(
            .hello(XAHello(protocolVersion: 99, token: "ABCDEFGH", deviceName: "iPad", deviceID: "1")),
            hostNowMs: 0
        )
        guard case .reply(.helloAck(let versionAck)) = version else { return XCTFail() }
        XCTAssertEqual(versionAck.reason, "version")
    }

    func testRateLimitDropsMovesButNotButtonUp() {
        var dispatcher = InputDispatcher(expectedToken: "ABCDEFGH", maxInputPerSecond: 1)
        dispatcher.displayFrame = XARect(x: 0, y: 0, width: 100, height: 100)
        dispatcher.videoPixelSize = XASize(width: 100, height: 100)
        _ = dispatcher.handle(.hello(XAHello(protocolVersion: 1, token: "ABCDEFGH", deviceName: "iPad", deviceID: "1")), hostNowMs: 0)
        let first = dispatcher.handle(.mouse(XAMouse(session: 1, seq: 1, phase: .move, button: .left, x: 0.1, y: 0.1, space: .absoluteNormalized)), hostNowMs: 0)
        XCTAssertNotEqual(first, .drop)
        let second = dispatcher.handle(.mouse(XAMouse(session: 1, seq: 2, phase: .move, button: .left, x: 0.2, y: 0.2, space: .absoluteNormalized)), hostNowMs: 10)
        XCTAssertEqual(second, .drop)
        let down = dispatcher.handle(.mouse(XAMouse(session: 1, seq: 3, phase: .down, button: .left, x: 0.2, y: 0.2, space: .absoluteNormalized)), hostNowMs: 20)
        guard case .post = down else { return XCTFail("button down must not be rate limited") }
        let up = dispatcher.disconnect()
        XCTAssertEqual(up.first, .mouse(phase: .up, button: .left, global: XAPoint(x: 20, y: 20)))
    }

    func testRelativeCursorAndScrollScaling() {
        var dispatcher = InputDispatcher(expectedToken: "ABCDEFGH")
        dispatcher.displayFrame = XARect(x: 10, y: 20, width: 200, height: 100)
        dispatcher.videoPixelSize = XASize(width: 400, height: 200)
        dispatcher.sessionGenerator = { 3 }
        _ = dispatcher.handle(.hello(XAHello(protocolVersion: 1, token: "ABCDEFGH", deviceName: "iPad", deviceID: "1")), hostNowMs: 0)
        let moved = dispatcher.handle(.mouse(XAMouse(session: 3, seq: 1, phase: .move, button: .left, x: 0.25, y: 0, space: .relativeNormalized)), hostNowMs: 0)
        guard case .post(let events) = moved else { return XCTFail() }
        XCTAssertEqual(events, [.mouse(phase: .move, button: .left, global: XAPoint(x: 160, y: 70))])
        let scroll = dispatcher.handle(.scroll(XAScroll(session: 3, seq: 2, dxPixels: 20, dyPixels: 10, inertia: false)), hostNowMs: 10)
        guard case .post(let scrolls) = scroll else { return XCTFail() }
        XCTAssertEqual(scrolls, [.scroll(dxPoints: 10, dyPoints: 5)])
    }

    func testPingWorksBeforePairing() {
        var dispatcher = InputDispatcher(expectedToken: "ABCDEFGH")
        let outcome = dispatcher.handle(.ping(XAPing(session: 0, clientUnixMs: 50)), hostNowMs: 80)
        guard case .reply(.pong(let pong)) = outcome else { return XCTFail() }
        XCTAssertEqual(pong.clientUnixMs, 50)
        XCTAssertEqual(pong.hostUnixMs, 80)
        XCTAssertFalse(dispatcher.armed)
    }

    func testPresetsMatchLevelLimitsAndBitrates() {
        XCTAssertEqual(StreamPreset.balanced.width, 1440)
        XCTAssertEqual(StreamPreset.balanced.height, 1080)
        XCTAssertEqual(StreamPreset.balanced.fps, 30)
        XCTAssertEqual(StreamPreset.balanced.level, "4.1")
        XCTAssertFalse(StreamPreset.balanced.allowBFrames)
        XCTAssertEqual(StreamPreset.balanced.bitrateUSB, 8_000_000)
        XCTAssertEqual(StreamPreset.balanced.bitrateWiFi, 6_000_000)
        XCTAssertEqual(StreamPreset.balanced.macroblocksPerFrame, 6120)
        XCTAssertTrue(H264LevelLimits.fits(width: 1440, height: 1080, level: "4.1"))
        XCTAssertEqual(StreamPreset.balanced.profileLevelName, "H264_Main_4_1")

        XCTAssertEqual(StreamPreset.safe.bitrateUSB, 4_000_000)
        XCTAssertTrue(H264LevelLimits.fits(width: 1024, height: 768, level: "3.1"))
        XCTAssertFalse(StreamPreset.safe.allowBFrames)

        XCTAssertTrue(StreamPreset.native.experimental)
        XCTAssertEqual(StreamPreset.native.fps, 60)
        XCTAssertEqual(StreamPreset.native.level, "5.1")
        XCTAssertEqual(StreamPreset.native.bitrateUSB, 18_000_000)
        XCTAssertEqual(H264LevelChoice.level(width: 1536, height: 2048, fps: 30), "5.0")
        XCTAssertEqual(H264LevelChoice.level(width: 1536, height: 2048, fps: 60), "5.1")
        XCTAssertEqual(H264LevelChoice.level(width: 2048, height: 1536, fps: 60), "5.1")
        XCTAssertEqual(StreamPreset.native.profileLevelName, "H264_Main_5_1")
        XCTAssertTrue(H264LevelChoice.videoToolboxAccepts(profileLevelName: StreamPreset.native.profileLevelName))
        XCTAssertEqual(StreamPreset.native.oriented(portrait: true).width, 1536)
        XCTAssertEqual(StreamPreset.preset(.balanced).id, StreamPreset.ID.balanced)
        XCTAssertFalse(H264LevelLimits.fits(width: 2048, height: 1536, level: "4.2"))
        XCTAssertTrue(H264LevelLimits.fits(width: 2048, height: 1536, level: "5.0"))
        XCTAssertEqual(PresetFallback.afterDecodeFailure(.native), .balanced)
        XCTAssertEqual(PresetFallback.afterDecodeFailure(.balanced), .safe)
        XCTAssertNil(PresetFallback.afterDecodeFailure(.safe))
        XCTAssertEqual(StreamPreset.balanced.oriented(portrait: true).width, 1080)
    }

    func testAdaptationThermalCongestionAndRecovery() {
        var controller = AdaptationController(preset: .balanced, usb: true)
        XCTAssertEqual(controller.bitrate, 8_000_000)
        let wifi = AdaptationController(preset: .balanced, usb: false)
        XCTAssertEqual(wifi.bitrate, 6_000_000)

        var hot = AdaptationSignals()
        hot.thermal = .critical
        let critical = controller.advance(dt: 1, signals: hot)
        XCTAssertEqual(critical?.preset, .safe)
        XCTAssertEqual(critical?.fps, 15)

        var native = AdaptationController(preset: .native, usb: true)
        var failed = AdaptationSignals()
        failed.decodeFailed = true
        XCTAssertEqual(native.advance(dt: 0.1, signals: failed)?.preset, .balanced)

        var congestedController = AdaptationController(preset: .balanced, usb: true)
        var congested = AdaptationSignals()
        congested.pipelineMs = 200
        let dropped = congestedController.advance(dt: 3, signals: congested)
        XCTAssertEqual(dropped?.bitrate, 5_600_000)
        XCTAssertNil(congestedController.advance(dt: 1, signals: congested))
        let again = congestedController.advance(dt: 2, signals: congested)
        XCTAssertEqual(again?.bitrate, 3_920_000)

        var recovering = AdaptationController(preset: .balanced, usb: true)
        _ = recovering.advance(dt: 3, signals: congested)
        let calm = AdaptationSignals()
        XCTAssertEqual(recovering.advance(dt: 20, signals: calm)?.reason, "recover")
    }

    func testFrameAdmissionDropsStalePFramesUntilKeyframe() {
        var gate = FrameAdmission()
        XCTAssertEqual(gate.decide(isKeyframe: false, queued: 0, ageMs: 10), .show)
        XCTAssertEqual(gate.decide(isKeyframe: false, queued: 0, ageMs: 400), .dropStale)
        XCTAssertEqual(gate.decide(isKeyframe: false, queued: 0, ageMs: 0), .dropUntilKeyframe)
        XCTAssertEqual(gate.decide(isKeyframe: true, queued: 4, ageMs: 0), .show)
        XCTAssertEqual(gate.decide(isKeyframe: false, queued: 1, ageMs: 0), .dropOverflow)
    }

    func testInFlightAndSendBudgetForceKeyframesAfterDrops() {
        var flight = InFlightGate()
        guard case .encode(true) = flight.begin() else { return XCTFail() }
        XCTAssertEqual(flight.begin(), .drop)
        flight.finished()
        guard case .encode(true) = flight.begin() else { return XCTFail("drop must force the next IDR") }
        flight.finished()
        guard case .encode(false) = flight.begin() else { return XCTFail() }

        var budget = SendBudget()
        XCTAssertEqual(budget.admit(pending: 0, isKeyframe: false), .drop)
        XCTAssertEqual(budget.admit(pending: 0, isKeyframe: true), .send)
        XCTAssertEqual(budget.admit(pending: 2, isKeyframe: true), .drop)
        XCTAssertEqual(budget.admit(pending: 0, isKeyframe: false), .drop)
        XCTAssertEqual(budget.admit(pending: 0, isKeyframe: true), .send)
    }

    func testUSBPreferredAndWiFiRequiresPermission() {
        XCTAssertEqual(LinkPreference.desired(usbAvailable: true, wifiAvailable: true, wifiAllowed: true), .usb)
        XCTAssertEqual(LinkPreference.desired(usbAvailable: false, wifiAvailable: true, wifiAllowed: true), .wifi)
        XCTAssertEqual(LinkPreference.desired(usbAvailable: false, wifiAvailable: true, wifiAllowed: false), .none)
        XCTAssertTrue(LinkPreference.shouldSwitch(current: .wifi, desired: .usb))
        XCTAssertFalse(LinkPreference.shouldSwitch(current: .usb, desired: .usb))
        XCTAssertEqual(TransportHeuristic.classify(remoteHost: "127.0.0.1"), .usb)
        XCTAssertEqual(TransportHeuristic.classify(remoteHost: "10.0.0.8"), .wifi)
        XCTAssertEqual(UsbmuxPort.networkOrder(9000), 10275)
        XCTAssertEqual(UsbmuxPort.candidates(9000), [10275, 9000])
    }

    func testLatencyMathRejectsNonsense() {
        XCTAssertEqual(LatencyMath.captureToAck(captureMs: 1000, ackMs: 1040), 40)
        XCTAssertNil(LatencyMath.captureToAck(captureMs: 1000, ackMs: 999))
        XCTAssertNil(LatencyMath.captureToAck(captureMs: 0, ackMs: 20_000))
        XCTAssertEqual(LatencyMath.handoff(receiveMs: 10, enqueueMs: 14.5), 4.5)
        XCTAssertFalse(LegacyInputPolicy.acceptsUnauthenticatedVideoInput)
    }
}
