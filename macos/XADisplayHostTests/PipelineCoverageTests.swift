@preconcurrency import AppKit
@preconcurrency import CoreVideo
@preconcurrency import Darwin
import XADisplayProtocol
import XCTest

@testable import XADisplayHost

@MainActor
final class PipelineCoverageTests: XCTestCase {
    func testEncoderUsbmuxWindowsAndSettings() {
        let encoder = H264Encoder()
        _ = encoder.start(width: 640, height: 360, fps: 30, bitrate: 2_000_000, profileLevel: "H264_Main_AutoLevel")
        var pixel: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 640, 360, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, nil, &pixel)
        if let pixel { encoder.encode(pixel, captureMs: 1) }
        encoder.updateBitrate(1_500_000)
        encoder.stop()
        _ = UsbmuxClient.listUSBDevices()
        if let fd = UsbmuxClient.connect(deviceID: 1, port: 1) { close(fd) }
        var descriptors = [Int32](repeating: 0, count: 2)
        if Darwin.pipe(&descriptors) == 0 {
            let stream = FDStream(fd: descriptors[0])
            stream.onData = { _ in }
            stream.onClose = {}
            stream.send(Data([1, 2, 3, 4]))
            Thread.sleep(forTimeInterval: 0.05)
            stream.closeStream()
            close(descriptors[1])
        }
        let frame = XARect(x: 0, y: 0, width: 1440, height: 1080)
        let main = WindowMover.mainDisplayFrame()
        _ = WindowMover.windows()
        _ = WindowMover.catalog(on: frame)
        _ = WindowMover.displayFrame(CGMainDisplayID())
        _ = WindowMover.recover(from: frame, to: main)
        _ = WindowMover.apply(zone: .full, virtual: frame, main: main)
        _ = WindowMover.tile(.bottomRight, on: frame)
        _ = WindowMover.fillToggle(on: frame)
        _ = WindowMover.pressTraffic(.pressZoom, on: frame)
        _ = WindowMover.pressMenu(index: 0)
        _ = WindowMover.pressExtra(matching: "Control Center")
        _ = WindowMover.resize(windowIndex: 0, corner: .topLeft, translation: XAPoint(x: 8, y: 8), on: frame)
        var document = XASettingsDocument.defaults
        document.audioMode = AudioRouteMode.selected.rawValue
        document.features.custom.enabled = true
        let panel = HostSettingsPanel(document: document)
        panel.apps = [("com.apple.finder", "Finder")]
        panel.selectedBundles = ["com.apple.finder"]
        panel.onChange = { _ in }
        panel.onRevoke = {}
        panel.onScreen = {}
        panel.onAccessibility = {}
        panel.onToggleApp = { _ in }
        panel.update(document)
        visit(panel.window.contentView)
        let flow = OnboardingFlow()
        flow.pairingCode = "ABCD2345"
        var finished = false
        flow.onFinish = { finished = true }
        flow.show()
        for _ in 0..<4 {
            let buttons = flow.window.contentView?.subviews.compactMap { $0 as? NSButton } ?? []
            buttons.first { ["Continue", "Waiting", "Done"].contains($0.title) }?.performClick(nil)
        }
        XCTAssertTrue(finished)
        let sender = UDPVideoSender()
        sender.connect(host: "127.0.0.1")
        sender.retransmit([])
        sender.stop()
    }

    func testCaptureAndAudioStartFailClosed() async {
        let capture = CapturePipeline()
        do {
            try await capture.start(displayID: 0, width: 640, height: 360, fps: 30, bitrate: 1_000_000, profileLevel: "H264_Main_AutoLevel", audio: false)
        } catch {
            capture.stop()
        }
        capture.updateBitrate(800_000)
        capture.stop()
        let audio = AudioCapture()
        await audio.start(displayID: 0, choice: .includingBundles([]))
        await audio.start(displayID: CGMainDisplayID(), choice: .allApplications)
        audio.stop()
    }

    private func visit(_ view: NSView?) {
        guard let view else { return }
        if let button = view as? NSButton { button.performClick(nil) }
        if let slider = view as? NSSlider, let target = slider.target as? NSObject, let action = slider.action {
            slider.doubleValue = min(slider.maxValue, slider.minValue + 1)
            _ = target.perform(action, with: slider)
        }
        if let popup = view as? NSPopUpButton, let target = popup.target as? NSObject, let action = popup.action {
            popup.selectItem(at: 0)
            _ = target.perform(action, with: popup)
        }
        for child in view.subviews { visit(child) }
    }
}
