import XCTest

@testable import XADisplayProtocol

final class BehaviorExtraTests: XCTestCase {
    func testMagnifierThreeFingerSnapAndDrawer() {
        var glass = Magnifier()
        glass.pinch(by: 2, around: XAPoint(x: 0.5, y: 0.5))
        let origin = glass.videoNormalized(viewNormalized: XAPoint(x: 0, y: 0))
        XCTAssertEqual(origin.x, 0.25, accuracy: 0.0001)
        XCTAssertEqual(origin.y, 0.25, accuracy: 0.0001)
        let center = glass.videoNormalized(viewNormalized: XAPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(center.x, 0.5, accuracy: 0.0001)
        glass.pinch(by: 0.1, around: XAPoint(x: 0.2, y: 0.2))
        XCTAssertEqual(glass.scale, 1, accuracy: 0.0001)

        XCTAssertEqual(ThreeFingerMapper.action(dx: -40, dy: 5), .undo)
        XCTAssertEqual(ThreeFingerMapper.action(dx: 40, dy: 0), .redo)
        XCTAssertEqual(ThreeFingerMapper.action(dx: 2, dy: -30), .copy)
        XCTAssertEqual(ThreeFingerMapper.action(dx: 0, dy: 30), .paste)
        let undo = ThreeFingerMapper.intents(for: .undo)
        guard case .key(.down, 6, .command, _) = undo[0] else { return XCTFail() }

        let virtual = XARect(x: 0, y: 0, width: 1440, height: 1080)
        let main = XARect(x: 0, y: 0, width: 1600, height: 1000)
        XCTAssertEqual(WindowSnap.frame(zone: .leftHalf, virtualDisplay: virtual, mainDisplay: main).width, 720, accuracy: 0.001)
        XCTAssertEqual(WindowSnap.flick(dx: -200, dy: 10, speed: 1200), .leftHalf)
        XCTAssertNil(WindowSnap.flick(dx: -200, dy: 10, speed: 100))
        XCTAssertFalse(TouchGestureRouter.titleBarFill(enabled: true, normalizedY: 0.02, tapCount: 2))
        XCTAssertTrue(TouchGestureRouter.edgeDrawer(enabled: true, startX: 8, viewWidth: 1024, translationX: 40, sidebarOnLeft: true))
        XCTAssertFalse(TouchGestureRouter.edgeDrawer(enabled: true, startX: 8, viewWidth: 1024, translationX: 40, sidebarOnLeft: false))

        var library = PresetLibrary()
        library.save(SavedDisplayPreset(name: "Night", preset: .safe, portrait: false))
        XCTAssertEqual(library.named("Night")?.preset, .safe)
        library.enabled = false
        XCTAssertNil(library.named("Night"))
        XCTAssertEqual(CommandStripItem.standard.first { $0.id == "fill" }?.windowAction, .fill)
        XCTAssertEqual(XAFeatureSettings().requirePairing, true)
        XCTAssertEqual(XAFeatureSettings().clipboardSync, false)
        XCTAssertEqual(XAFeatureSettings().audio, false)
    }

    func testThermalMapping() {
        XCTAssertEqual(ThermalBucket.from(processInfoRawValue: 0), .nominal)
        XCTAssertEqual(ThermalBucket.from(processInfoRawValue: 3), .critical)
        XCTAssertEqual(ThermalBucket.from(processInfoRawValue: 9), .unknown)
    }
    func testWindowRecoveryAndDiagnosticsRedaction() throws {
        let display = XARect(x: -1440, y: 0, width: 1440, height: 1080)
        let main = XARect(x: 0, y: 0, width: 1600, height: 900)
        let onDisplay = WindowSnapshot(id: 1, ownerPID: 10, title: "Notes", bounds: XARect(x: -1400, y: 100, width: 200, height: 200))
        let elsewhere = WindowSnapshot(id: 2, ownerPID: 11, title: "Mail", bounds: XARect(x: 40, y: 40, width: 100, height: 100))
        XCTAssertEqual(WindowRecovery.stranded([onDisplay, elsewhere], on: display).map(\.id), [1])
        let moved = WindowRecovery.relocate(onDisplay, from: display, to: main)
        XCTAssertEqual(moved.origin.x, 40, accuracy: 0.0001)
        XCTAssertEqual(moved.origin.y, 100, accuracy: 0.0001)

        let relative = LayoutMath.relative(bounds: onDisplay.bounds, display: display)
        let snapshot = LayoutSnapshot(windows: [LayoutWindow(title: "Notes", owner: "Notes", relative: relative)])
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(LayoutSnapshot.self, from: data)
        XCTAssertEqual(LayoutMath.absolute(relative: decoded.windows[0].relative, display: display).origin.x, -1400, accuracy: 0.0001)

        let report = DiagnosticsText.render(
            DiagnosticsSnapshot(
                appVersion: "1.0.0", transport: "usb", preset: "balanced",
                permissions: ["accessibility": false, "screenRecording": true],
                pairingToken: "ABCD-EFGH", thermal: "nominal", battery: "80%",
                notes: ["capture started"]
            ))
        XCTAssertFalse(report.contains("ABCD"))
        XCTAssertTrue(report.contains("••••GH"))
        XCTAssertTrue(report.contains(DiagnosticsText.honesty))
        XCTAssertTrue(report.contains("not a glass-to-glass"))
    }

    func testCursorCacheEvictsAndRejectsOversize() {
        var cache = CursorCache(maxEntries: 2, maxBytes: 8)
        XCTAssertFalse(cache.store(id: "big", png: Data(repeating: 1, count: 9)))
        XCTAssertTrue(cache.store(id: "a", png: Data([1])))
        XCTAssertTrue(cache.store(id: "b", png: Data([2])))
        XCTAssertTrue(cache.store(id: "c", png: Data([3])))
        XCTAssertNil(cache.image(id: "a"))
        XCTAssertEqual(cache.image(id: "c"), Data([3]))
    }

    func testFeatureTogglesGateClipboardWindowsAndOpenPairing() {
        var locked = InputDispatcher(expectedToken: "ABCDEFGH", clipboardEnabled: false, windowActionsEnabled: false)
        locked.displayFrame = XARect(x: 0, y: 0, width: 100, height: 100)
        _ = locked.handle(.hello(XAHello(protocolVersion: 1, token: "ABCDEFGH", deviceName: "iPad", deviceID: "1")), hostNowMs: 0)
        XCTAssertEqual(locked.handle(.clipboard(XAClipboard(session: 1, seq: 1, revision: 1, text: "secret")), hostNowMs: 0), .drop)
        XCTAssertEqual(locked.handle(.window(XAWindowCommand(session: 1, seq: 2, action: .fill)), hostNowMs: 0), .drop)
        locked.clipboardEnabled = true
        locked.windowActionsEnabled = true
        guard case .post(let copied) = locked.handle(.clipboard(XAClipboard(session: 1, seq: 3, revision: 4, text: "ok")), hostNowMs: 10) else {
            return XCTFail("clipboard")
        }
        XCTAssertEqual(copied, [.clipboard(text: "ok", revision: 4)])
        guard case .post(let snapped) = locked.handle(.window(XAWindowCommand(session: 1, seq: 4, action: .snapRight)), hostNowMs: 20) else {
            return XCTFail("window")
        }
        XCTAssertEqual(snapped, [.window(.snapRight)])

        var open = InputDispatcher(expectedToken: "ABCDEFGH", requirePairing: false)
        let unpaired = open.handle(.hello(XAHello(protocolVersion: 1, token: "", deviceName: "iPad", deviceID: "1", flags: 0)), hostNowMs: 0)
        guard case .reply(.helloAck(let ack)) = unpaired else { return XCTFail() }
        XCTAssertTrue(ack.accepted)
        var stillGuarded = InputDispatcher(expectedToken: "ABCDEFGH", requirePairing: false)
        let guarded = stillGuarded.handle(.hello(XAHello(protocolVersion: 1, token: "", deviceName: "iPad", deviceID: "1", flags: XAHello.flagRequiresPairing)), hostNowMs: 0)
        guard case .reply(.helloAck(let guardedAck)) = guarded else { return XCTFail() }
        XCTAssertFalse(guardedAck.accepted)
        XCTAssertFalse(AudioPolicy.accept(enabled: false, armed: true, byteCount: 4, channels: 2))
        XCTAssertTrue(AudioPolicy.accept(enabled: true, armed: true, byteCount: 4, channels: 2))
        XCTAssertFalse(ClipboardPolicy.accept(enabled: true, armed: false, utf8Count: 3))
    }
}
