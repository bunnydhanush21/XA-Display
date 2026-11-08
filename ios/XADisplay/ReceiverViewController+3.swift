import AVFoundation
import UIKit
import XADisplayProtocol

extension ReceiverViewController {
    func layoutVideo() {
        if layingVideo { return }
        layingVideo = true
        defer { layingVideo = false }
        let host = view.bounds
        let devicePortrait = host.height > host.width
        let wantPortrait =
            OrientationPolicy.resolved(
                device: devicePortrait ? "portrait" : "landscape",
                follow: features.followRotation,
                lock: features.orientationLock
            ) == "portrait"
        let rotate = !letterboxFallback && features.rotationMode == "stream" && wantPortrait && devicePortrait
        let placed = VideoPlacement.frame(host: host, rotateClockwise: rotate)
        let unchanged =
            videoView.bounds.equalTo(placed.bounds)
            && abs(videoView.center.x - placed.center.x) < 0.5
            && abs(videoView.center.y - placed.center.y) < 0.5
            && streamTransform == placed.transform
        if unchanged {
            applyMagnifier()
            return
        }
        videoView.transform = .identity
        videoView.bounds = placed.bounds
        videoView.center = placed.center
        streamTransform = placed.transform
        applyMagnifier()
    }
    func noteOrientation(_ device: String) {
        guard OrientationPolicy.resolved(device: device, follow: features.followRotation, lock: features.orientationLock) != nil else { return }
        let resolved = OrientationPolicy.resolved(device: device, follow: features.followRotation, lock: features.orientationLock) ?? device
        guard orientDebounce.note(resolved, now: CACurrentMediaTime()) else { return }
        orientTimer?.invalidate()
        orientTimer = Timer.scheduledTimer(withTimeInterval: OrientationDebounce.seconds, repeats: false) { [weak self] _ in
            self?.sendOrientationIfDue()
        }
    }
    func sendOrientationIfDue() {
        guard receiver.isConnected, xaHost else { return }
        guard let orientation = orientDebounce.due(now: CACurrentMediaTime()) else { return }
        let videoPortrait = videoSize.height > videoSize.width && videoSize != .zero
        if features.rotationMode == "resolution", (orientation == "portrait") != videoPortrait {
            receiver.holdPictureUntilKeyframe()
        }
        receiver.sendOrientation(orientation, mode: features.rotationMode)
    }
    func applyMagnifier() {
        guard features.pinchMagnifier, magnifier.scale > 1.01 else {
            videoView.transform = streamTransform
            return
        }
        let scale = CGFloat(magnifier.scale)
        let tx = CGFloat(0.5 - magnifier.center.x) * videoView.bounds.width
        let ty = CGFloat(0.5 - magnifier.center.y) * videoView.bounds.height
        let zoom = CGAffineTransform(translationX: tx, y: ty).scaledBy(x: scale, y: scale)
        videoView.transform = streamTransform.concatenating(zoom)
    }
    func layoutCursor() {
        let rect = videoView.bounds
        cursorLayer.position = CGPoint(x: rect.minX + cursorNorm.x * rect.width, y: rect.minY + cursorNorm.y * rect.height)
        cursorLayer.isHidden = !cursorVisible
    }
    func releaseModifiers() {
        for bit in heldModifiers.individualBits {
            input.send(intent: .modifier(bit, down: false))
            sidebar.setModifier(bit, on: false)
        }
        heldModifiers = []
    }
    func publishHealth() {
        input.sendPing()
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        let state: String
        switch UIDevice.current.batteryState {
        case .charging: state = "charging"
        case .full: state = "full"
        case .unplugged: state = "unplugged"
        default: state = "unknown"
        }
        let thermal = ThermalBucket.from(processInfoRawValue: ProcessInfo.processInfo.thermalState.rawValue)
        let battery = batteryLoop.tick(enabledTelemetry: features.batteryTelemetry, chargeLimit: features.chargeLimit, config: chargeConfig)
        if features.batteryTelemetry, !battery.text.isEmpty {
            receiver.sendBattery(text: battery.text, heat: battery.heat)
        } else {
            receiver.sendBattery(text: "", heat: false)
        }
        if let careWarning = batteryLoop.warning {
            warningLabel.isHidden = false
            warningLabel.text = careWarning
        } else {
            warningLabel.isHidden = thermal != .serious && thermal != .critical
            warningLabel.text = thermal == .critical ? "Very warm. The Mac should drop quality." : "Warm. Quality may step down."
        }
        receiver.sendHealth(
            HealthReport(
                thermal: thermal,
                batteryFraction: level < 0 ? nil : Double(level),
                batteryState: state,
                fpsDelivered: fps,
                decodeFails: 0
            ))
        refreshStats()
    }
    func refreshStats() {
        let pipeline = pipelineMs.map { String(format: "%.0f ms", $0) } ?? "—"
        let rtt = rttMs.map { String(format: "%.0f ms", $0) } ?? "—"
        let batteryLines = features.batteryTelemetry ? "\n" + batteryLoop.lastText : ""
        let measured = pipelineMs == nil ? "not measured yet" : "\(pipeline) measured, includes return, not glass-to-glass"
        statsLabel.text =
            "  FPS \(String(format: "%.0f", fps)) delivered\n  Handoff \(String(format: "%.1f", handoffMs)) ms\n  Link delay \(measured)\n  Input RTT \(rtt)\n  \(streamLabel)\(batteryLines)  "
    }
    @objc func foreground() {
        guard !userPaused else { return }
        receiver.ensureListening()
        input.ensureListening()
    }
    @objc func backgrounded() {
        input.sendRelease()
        releaseModifiers()
        UIApplication.shared.isIdleTimerDisabled = false
        let task = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            UIApplication.shared.endBackgroundTask(task)
        }
    }
    func modifiers(from flags: UIKeyModifierFlags) -> XAModifierMask {
        var mask = XAModifierMask()
        if flags.contains(.shift) { mask.insert(.shift) }
        if flags.contains(.control) { mask.insert(.control) }
        if flags.contains(.alternate) { mask.insert(.option) }
        if flags.contains(.command) { mask.insert(.command) }
        return mask
    }
    func videoReceiver(_ receiver: VideoReceiver, statusDidChange status: String) {
        if !receiver.isConnected { statusLabel.text = status }
    }
    func videoReceiver(_ receiver: VideoReceiver, connected: Bool, transport: TransportKind) {
        connectionOverlay.isHidden = connected
        UIApplication.shared.isIdleTimerDisabled = connected
        if connected {
            orientTimer?.invalidate()
            if let resolved = OrientationPolicy.resolved(device: receiver.orientation, follow: features.followRotation, lock: features.orientationLock) {
                orientDebounce.adopt(resolved)
            }
        }
        updateKeepalive()
        statusLabel.isHidden = connected
        if connected {
            switch transport {
            case .usb: statusLabel.text = "USB"
            case .wifi: statusLabel.text = "Wi-Fi"
            case .none: statusLabel.text = "Connected"
            }
            statusLabel.isHidden = false
        } else if !userPaused {
            statusLabel.text = "Reconnecting"
            statusLabel.isHidden = false
            releaseModifiers()
            input.send(intent: .mouse(phase: .up, button: .left, x: 0, y: 0, space: .relativeNormalized))
            input.send(intent: .mouse(phase: .up, button: .right, x: 0, y: 0, space: .relativeNormalized))
            chrome.loupe.hide()
            resizing = nil
        }
    }
    func videoReceiver(_ receiver: VideoReceiver, videoSizeDidChange size: CGSize) {
        videoSize = size
        streamLabel = "\(Int(size.width))×\(Int(size.height))"
        refreshStats()
    }
    func videoReceiver(_ receiver: VideoReceiver, cursor point: CGPoint, visible: Bool) {
        guard !features.trackpadMode, !localCursor else { return }
        cursorNorm = point
        cursorVisible = visible
        layoutCursor()
    }
    func videoReceiver(_ receiver: VideoReceiver, cursorImage image: UIImage, id: String) {
        cursorLayer.contents = image.cgImage
        cursorLayer.bounds = CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
    }
    func videoReceiver(_ receiver: VideoReceiver, stats: ReceiverStats) {
        fps = stats.fpsDelivered
        handoffMs = stats.handoffMs
        refreshStats()
    }
    func videoReceiverBecameXAHost(_ receiver: VideoReceiver) {
        xaHost = true
        sendAuth()
        sendOrientationIfDue()
    }
    func videoReceiver(_ receiver: VideoReceiver, orientation: String, mode: String, letterbox: Bool) {
        letterboxFallback = letterbox
        if mode == "stream" || letterbox {
            receiver.releasePictureHold()
        } else if mode == "resolution" {
            receiver.holdPictureUntilKeyframe()
        }
        view.setNeedsLayout()
    }
    func videoReceiver(_ receiver: VideoReceiver, stream: StreamAnnouncement) {
        streamLabel = "\(stream.preset) \(stream.width)×\(stream.height)@\(stream.fps)"
        if stream.experimental { streamLabel += " experimental" }
        refreshStats()
    }
    func videoReceiver(_ receiver: VideoReceiver, metrics: XAMetrics) {
        pipelineMs = metrics.captureToAckMs
        refreshStats()
    }
    func videoReceiver(_ receiver: VideoReceiver, windows body: String) {
        windowFrames = ChromeWire.parseWindows(body)
        chrome.layout(windows: windowFrames.map { self.viewRect(for: $0) }, assist: assist)
    }
    func videoReceiver(_ receiver: VideoReceiver, menus body: String) {
        menuTitles = ChromeWire.parseMenus(body)
        if chrome.menuVisible { chrome.showMenus(menuTitles, large: assist.largeButtons) }
    }
    func videoReceiver(_ receiver: VideoReceiver, frontBundle bundle: String) {
        frontBundle = bundle
    }
    func resizeHit(at point: CGPoint) -> (index: Int, corner: ResizeCorner)? {
        guard assist.windowChrome else { return nil }
        let xa = XAPoint(x: Double(point.x), y: Double(point.y))
        for (index, frame) in windowViewFrames().enumerated() {
            if let corner = WindowChrome.resizeCorner(point: xa, window: frame) { return (index, corner) }
        }
        return nil
    }
    func windowViewFrames() -> [XARect] {
        windowFrames.map { normalized in
            let rect = viewRect(for: normalized)
            return XARect(x: Double(rect.minX), y: Double(rect.minY), width: Double(rect.width), height: Double(rect.height))
        }
    }
    func viewRect(for normalized: XARect) -> CGRect {
        let content = CoordinateMapper.contentRect(
            view: XASize(width: Double(videoView.bounds.width), height: Double(videoView.bounds.height)),
            video: XASize(width: Double(max(videoSize.width, 1)), height: Double(max(videoSize.height, 1)))
        )
        return CGRect(
            x: CGFloat(content.minX + normalized.minX * content.width),
            y: CGFloat(content.minY + normalized.minY * content.height),
            width: CGFloat(normalized.width * content.width),
            height: CGFloat(normalized.height * content.height)
        )
    }
    func titleHeightNormalized() -> Double {
        let height = contentSize().height
        guard height > 1 else { return 0.04 }
        return WindowChrome.titleBarPoints / height
    }
    func showLoupe(at finger: CGPoint) {
        if loupeImage == nil {
            UIGraphicsBeginImageContextWithOptions(videoView.bounds.size, true, 1)
            videoView.drawHierarchy(in: videoView.bounds, afterScreenUpdates: false)
            loupeImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
        }
        guard let image = loupeImage else { return }
        chrome.loupe.show(image: image, around: finger, finger: finger)
    }
    func inputChannel(_ channel: InputChannel, armed: Bool, reason: String) {
        if armed { rememberConnectedMac() }
        if !armed {
            statusLabel.isHidden = false
            statusLabel.text = reason == "token" || reason == "empty" ? "Pairing rejected" : "Not paired (\(reason))"
        }
    }
    func inputChannel(_ channel: InputChannel, clipboard text: String, revision: UInt64) {
        guard features.clipboardSync else { return }
        clipboard.applyRemote(text: text, revision: revision)
    }
    func inputChannel(_ channel: InputChannel, audio: XAAudio) {
        guard features.audio else { return }
        self.audio.start()
        self.audio.push(audio)
    }
}
