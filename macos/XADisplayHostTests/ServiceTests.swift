@preconcurrency import AppKit
import XADisplayProtocol
import XCTest

@testable import XADisplayHost

@MainActor
final class ServiceTests: XCTestCase {
    func testDisplayConnectionClipboardAndInput() {
        let display = DisplayService()
        let portrait = display.active(preset: .balanced, portrait: true, custom: CustomDisplaySettings())
        XCTAssertEqual(portrait.width, 1080)
        XCTAssertEqual(portrait.height, 1440)
        let custom = display.active(preset: .balanced, portrait: false, custom: CustomDisplaySettings(enabled: true, width: 1280, height: 800, fps: 24, bitrate: 4_000_000))
        XCTAssertEqual(custom.width, 1280)
        XCTAssertEqual(custom.scale, 1)
        let plan = display.plan(currentPortrait: false, requested: "portrait", follow: true, lock: "none", mode: "resolution", preset: .balanced)
        XCTAssertEqual(plan, .reconfigure(width: 1080, height: 1440))
        let connection = ConnectionService()
        XCTAssertEqual(connection.link(running: true, userPaused: false, autoUSB: true, transport: .none, usb: true, wifiHost: nil, wifiAllowed: true), .usb)
        XCTAssertNil(connection.link(running: true, userPaused: true, autoUSB: true, transport: .none, usb: true, wifiHost: nil, wifiAllowed: true))
        XCTAssertEqual(connection.link(running: true, userPaused: false, autoUSB: true, transport: .none, usb: false, wifiHost: "10.0.0.2", wifiAllowed: true), .wifi)
        let clipboard = ClipboardService()
        XCTAssertEqual(clipboard.outbound(sync: true, armed: true, changeCount: 2, lastCount: 1, text: "hello"), "hello")
        XCTAssertNil(clipboard.outbound(sync: false, armed: true, changeCount: 2, lastCount: 1, text: "hello"))
        XCTAssertTrue(AudioService().shouldCapture(enabled: true, displayID: 1))
        XCTAssertFalse(AudioService().shouldCapture(enabled: true, displayID: 0))
        var gate = ChannelGate(requireAuth: true)
        XCTAssertFalse(InputService().allowsVideo(gate))
        XCTAssertEqual(InputService().failure(for: .xaSettings("{}"), allowed: false), .pairing)
        XCTAssertNil(InputService().failure(for: .hello(LegacyHello(pixelsWide: 1, pixelsHigh: 1, scale: 2, device: "iPad", id: "a", orientation: "landscape")), allowed: false))
        _ = gate.acceptVideo(token: "ABCD2345", nonce: "pad", proof: ChannelAuth.proof(token: "ABCD2345", channel: .video, nonce: "pad"))
        XCTAssertTrue(InputService().allowsVideo(gate))
        let fixed = FixedPermissions(screenRecording: false, accessibility: true).snapshot()
        XCTAssertFalse(fixed.screenRecording)
        XCTAssertTrue(fixed.accessibility)
    }

    func testMenuSettingsAndOnboardingSnapshots() throws {
        let menu = MenuPopoverController()
        menu.refresh(
            MenuSnapshot(
                phase: .streaming, peerName: "iPad", transport: "usb", latency: "12 ms", fps: "30 fps", preset: "balanced", audio: true, clipboard: false, touch: true, lowLatency: true,
                screenRecording: true, accessibility: true))
        let menuView = try XCTUnwrap(menu.popover.contentViewController?.view)
        try writePNG(menuView, named: "mac-popover.png", size: NSSize(width: 320, height: 420))
        let settings = HostSettingsPanel(document: .defaults)
        try writePNG(try XCTUnwrap(settings.window.contentView), named: "mac-settings.png", size: NSSize(width: 640, height: 480))
        let flow = OnboardingFlow()
        flow.pairingCode = "ABCD2345"
        flow.show()
        try writePNG(try XCTUnwrap(flow.window.contentView), named: "mac-onboarding.png", size: NSSize(width: 520, height: 360))
    }

    func testDiagnosticsRedactsTheToken() {
        let text = DiagnosticsText.render(
            DiagnosticsSnapshot(
                appVersion: "1.0.0", transport: "usb", preset: "balanced", permissions: ["screenRecording": true], pairingToken: "ABCD2345", thermal: "mac", battery: "mac",
                notes: ["failure code=pairing"]))
        XCTAssertFalse(text.contains("ABCD2345"))
        XCTAssertTrue(text.contains("failure code=pairing") || text.contains("notes"))
        let zip = StoredZip.archive(name: "diagnostics.txt", data: Data(text.utf8))
        XCTAssertTrue(zip.starts(with: Data([0x50, 0x4B, 0x03, 0x04])))
    }

    private func writePNG(_ view: NSView, named name: String, size: NSSize) throws {
        view.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        prepareForSnapshot(view)
        window.orderFrontRegardless()
        window.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()
        window.display()
        if let cached = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: cached)
            if let data = cached.representation(using: .png, properties: [:]), data.count > 1000 {
                try write(data, named: name)
                return
            }
        }
        let pixelsWide = Int(size.width)
        let pixelsHigh = Int(size.height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: pixelsWide, height: pixelsHigh, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            XCTFail("Could not allocate the offscreen bitmap")
            return
        }
        NSGraphicsContext.saveGraphicsState()
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = graphics
        view.displayIgnoringOpacity(view.bounds, in: graphics)
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else {
            XCTFail("Could not read the offscreen bitmap")
            return
        }
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            XCTFail("Could not encode PNG")
            return
        }
        try write(data, named: name)
    }

    private func write(_ data: Data, named name: String) throws {
        guard let dir = Self.screenshotDirectory() else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        XCTAssertGreaterThan(data.count, 1000)
    }

    private func prepareForSnapshot(_ view: NSView) {
        view.wantsLayer = true
        if let field = view as? NSTextField {
            field.textColor = .white
            field.drawsBackground = false
        }
        if let button = view as? NSButton, button.title.isEmpty == false {
            button.attributedTitle = NSAttributedString(string: button.title, attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 13)])
        }
        for child in view.subviews { prepareForSnapshot(child) }
    }

    private static func screenshotDirectory() -> String? {
        if let dir = ProcessInfo.processInfo.environment["XA_SCREENSHOT_DIR"], !dir.isEmpty { return dir }
        let marker = "/tmp/xa-screenshot-dir"
        guard let text = try? String(contentsOfFile: marker, encoding: .utf8) else { return nil }
        let dir = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return dir.isEmpty ? nil : dir
    }
}
