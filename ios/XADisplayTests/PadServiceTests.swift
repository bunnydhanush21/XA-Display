import UIKit
import XADisplayProtocol
import XCTest

@testable import XADisplay

final class PadServiceTests: XCTestCase {
    func testRotationMappingClipboardAndSession() {
        let display = PadDisplayService()
        XCTAssertTrue(display.rotation(mode: "stream", portrait: true, follow: true, lock: "none", letterbox: false))
        XCTAssertFalse(display.rotation(mode: "resolution", portrait: true, follow: true, lock: "none", letterbox: false))
        XCTAssertFalse(display.rotation(mode: "stream", portrait: true, follow: true, lock: "none", letterbox: true))
        let mapped = PadInputService().normalized(
            point: XAPoint(x: 0, y: 0), view: XASize(width: 768, height: 1024), video: XASize(width: 1440, height: 1080), rotation: .clockwise90, pixelsPerPoint: 2)
        XCTAssertEqual(mapped?.y ?? -1, 1, accuracy: 0.01)
        XCTAssertTrue(PadAudioService().accepts(enabled: true, armed: true, byteCount: 4, channels: 2))
        XCTAssertFalse(PadAudioService().accepts(enabled: true, armed: false, byteCount: 4, channels: 2))
        XCTAssertTrue(PadClipboardService().accepts(enabled: true, armed: true, text: "copy"))
        XCTAssertFalse(PadClipboardService().accepts(enabled: false, armed: true, text: "copy"))
        let session = PadSession()
        session.apply(.beginConnect)
        XCTAssertEqual(session.phase, .connecting)
        session.apply(.authAccepted)
        XCTAssertEqual(session.phase, .streaming)
        XCTAssertFalse(PadConnectionService().overlayVisible(connected: true))
        XCTAssertEqual(PadConnectionService().phase(connected: false, paused: true), .userStop)
        var document = XASettingsDocument.defaults
        document.set(.bool(false), for: "display.follow")
        let merged = SettingsSync.apply(SettingsSync.encode(document), to: XASettingsDocument.defaults)
        XCTAssertFalse(merged.features.followRotation)
    }

    func testRenderedConnectionAndFirstRun() throws {
        let overlay = ConnectionOverlay(frame: CGRect(x: 0, y: 0, width: 768, height: 1024))
        overlay.show(macs: ["Office Mac"], code: "ABCD2345")
        try writePNG(overlay, named: "ipad-connection.png")
        let first = FirstRunController()
        first.loadViewIfNeeded()
        first.view.frame = CGRect(x: 0, y: 0, width: 768, height: 1024)
        first.view.layoutIfNeeded()
        try writePNG(first.view, named: "ipad-onboarding.png")
        let receiver = ReceiverViewController()
        receiver.loadViewIfNeeded()
        receiver.view.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
        receiver.view.layoutIfNeeded()
        try writePNG(receiver.view, named: "ipad-landscape.png")
    }

    private func writePNG(_ view: UIView, named name: String) throws {
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        let image = renderer.image { view.layer.render(in: $0.cgContext) }
        guard let data = image.pngData() else { return }
        guard let dir = ProcessInfo.processInfo.environment["XA_SCREENSHOT_DIR"], !dir.isEmpty else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        XCTAssertGreaterThan(data.count, 1000)
    }
}
