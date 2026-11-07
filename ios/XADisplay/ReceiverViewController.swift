import AVFoundation
import UIKit
import XADisplayProtocol

final class ReceiverViewController: UIViewController, VideoReceiverDelegate, InputChannelDelegate {
    private let videoView = VideoContainerView()
    private let sidebar = SidebarView()
    private let commandStrip = CommandStripView()
    private let statsLabel = StatsOverlay()
    private let statusLabel = UILabel()
    private let warningLabel = UILabel()
    private let precisionLabel = UILabel()
    private let keyInput = KeyInputView()
    private var receiver: VideoReceiver!
    private let input = InputChannel()
    private let clipboard = ClipboardBridge()
    private let audio = PCMPlayer()
    private var features = XAFeatureSettings()
    private var token = ""
    private var interpreter = DirectTouchInterpreter()
    private var magnifier = Magnifier()
    private var videoSize = CGSize.zero
    private var cursorNorm = CGPoint(x: 0.5, y: 0.5)
    private var cursorVisible = false
    private let cursorLayer = CALayer()
    private var heldModifiers = XAModifierMask()
    private var sidebarWidth: NSLayoutConstraint!
    private var sidebarLeading: NSLayoutConstraint!
    private var sidebarTrailing: NSLayoutConstraint!
    private var collapsed = false
    private var keyboardOn = false
    private var trackpad = TrackpadCursor()
    private var streamLabel = "waiting"
    private var handoffMs = 0.0
    private var pipelineMs: Double?
    private var rttMs: Double?
    private var fps = 0.0
    private var userPaused = false
    private var lastMove = XAPoint.zero
    private var lastMoveTime = 0.0
    private var xaHost = false
    private var healthTimer: Timer?

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let loaded = LocalSettings.load()
        token = loaded.token
        features = loaded.features
        interpreter = DirectTouchInterpreter(
            slop: features.gestureTuning.clamped().slop,
            doubleTapWindow: features.gestureTuning.clamped().doubleTapWindow,
            longPressDuration: features.gestureTuning.clamped().longPressDuration
        )
        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.isUserInteractionEnabled = false
        view.addSubview(videoView)
        NSLayoutConstraint.activate([
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoView.topAnchor.constraint(equalTo: view.topAnchor),
            videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        cursorLayer.bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
        cursorLayer.backgroundColor = UIColor.white.cgColor
        cursorLayer.cornerRadius = 9
        cursorLayer.isHidden = true
        videoView.layer.addSublayer(cursorLayer)

        sidebar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sidebar)
        sidebarWidth = sidebar.widthAnchor.constraint(equalToConstant: 168)
        sidebarLeading = sidebar.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        sidebarTrailing = sidebar.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: view.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebarWidth,
            sidebarLeading,
        ])
        wireSidebar()

        commandStrip.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(commandStrip)
        NSLayoutConstraint.activate([
            commandStrip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            commandStrip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            commandStrip.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            commandStrip.heightAnchor.constraint(equalToConstant: 52),
        ])
        commandStrip.onItem = { [weak self] item in self?.command(item) }

        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        warningLabel.translatesAutoresizingMaskIntoConstraints = false
        precisionLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .white
        statusLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        statusLabel.textAlignment = .center
        warningLabel.textColor = UIColor(red: 1, green: 0.8, blue: 0.4, alpha: 1)
        warningLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        warningLabel.textAlignment = .center
        warningLabel.isHidden = true
        precisionLabel.textColor = .white
        precisionLabel.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        precisionLabel.text = "Precision"
        precisionLabel.isHidden = true
        for label in [statsLabel, statusLabel, warningLabel, precisionLabel] {
            label.isUserInteractionEnabled = false
            view.addSubview(label)
        }
        NSLayoutConstraint.activate([
            statsLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            statsLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -64),
            warningLabel.topAnchor.constraint(equalTo: statsLabel.bottomAnchor, constant: 6),
            warningLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            precisionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            precisionLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        keyInput.isHidden = true
        view.addSubview(keyInput)
        keyInput.onText = { [weak self] text in
            for intent in TextEntry.insert(text) { self?.input.send(intent: intent) }
        }
        keyInput.onDelete = { [weak self] in
            for intent in TextEntry.delete() { self?.input.send(intent: intent) }
        }

        receiver = VideoReceiver(displayLayer: videoView.displayLayer)
        receiver.delegate = self
        input.delegate = self
        input.token = token
        input.requirePairing = features.requirePairing
        input.deviceName = UIDevice.current.name
        clipboard.enabled = features.clipboardSync
        clipboard.onLocalCopy = { [weak self] text in
            guard let self = self, self.features.clipboardSync else { return }
            self.input.sendClipboard(text: text, revision: UInt64(UIPasteboard.general.changeCount))
        }
        clipboard.start()
        addGestures()
        applyChrome()
        receiver.start()
        input.start()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.publishHealth()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(foreground), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(backgrounded), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    override var canBecomeFirstResponder: Bool { true }
    override var keyCommands: [UIKeyCommand]? {
        let inputs = ["z", "c", "v", "x", "a", "s", "\u{1b}", "UIKeyInputUpArrow", "UIKeyInputDownArrow", "UIKeyInputLeftArrow", "UIKeyInputRightArrow", "\t"]
        let flags: [UIKeyModifierFlags] = [.command, [.command, .shift], []]
        var commands: [UIKeyCommand] = []
        for input in inputs {
            for flag in flags where !(input.count == 1 && input >= "a" && input <= "z" && flag.isEmpty) {
                commands.append(UIKeyCommand(input: input, modifierFlags: flag, action: #selector(hardwareKey(_:))))
            }
        }
        return commands
    }

    @objc private func hardwareKey(_ command: UIKeyCommand) {
        let mask = modifiers(from: command.modifierFlags)
        let shortcut = KeyShortcut(input: command.input ?? "", modifiers: mask)
        for intent in shortcut.intents() { input.send(intent: intent) }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let scale = UIScreen.main.scale
        let bounds = UIScreen.main.bounds
        let wide = Int(bounds.width * scale)
        let high = Int(bounds.height * scale)
        let portrait = bounds.height > bounds.width
        receiver.devicePixelsWide = wide
        receiver.devicePixelsHigh = high
        receiver.deviceScale = Double(scale)
        receiver.orientation = portrait ? "portrait" : "landscape"
        if receiver.isConnected { receiver.announcePanel() }
        layoutCursor()
        applyMagnifier()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { feed(touches, .began, event) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { feed(touches, .moved, event) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { feed(touches, .ended, event) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { feed(touches, .cancelled, event) }

    private func feed(_ touches: Set<UITouch>, _ phase: TouchSample.Phase, _ event: UIEvent?) {
        guard let touch = touches.first else { return }
        let count = event?.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled }.count ?? 1
        let point = touch.location(in: videoView)
        let sample = TouchSample(time: touch.timestamp, phase: phase, location: XAPoint(x: Double(point.x), y: Double(point.y)), activeTouches: count)
        let gestures = interpreter.feed(sample) { [weak self] location in
            self?.normalize(location)
        }
        for gesture in gestures { perform(gesture) }
        if phase == .moved {
            let now = touch.timestamp
            lastMove = XAPoint(x: Double(point.x), y: Double(point.y))
            lastMoveTime = now
        }
    }

    private func perform(_ gesture: FingerGesture) {
        if features.trackpadMode {
            performTrackpad(gesture)
            return
        }
        if case .tap(let point) = gesture, TouchGestureRouter.titleBarFill(enabled: features.touchscreenGestures, normalizedY: point.y, tapCount: 2) {
            input.sendWindow(.fill)
            return
        }
        if case .drag(.ended, let point) = gesture, features.touchscreenGestures {
            let speed = xaHypot(point.x - lastMove.x, point.y - lastMove.y) * 1000
            if let zone = WindowSnap.flick(dx: point.x - lastMove.x, dy: point.y - lastMove.y, speed: speed, minimumSpeed: 0.8) {
                sendSnap(zone)
            }
        }
        if features.trackpadMode == false {
            forwardLegacy(gesture)
        }
        for intent in GestureMapper.intents(for: gesture) {
            input.send(intent: intent)
        }
    }

    private func performTrackpad(_ gesture: FingerGesture) {
        switch gesture {
        case .drag(.moved, _), .relativeMove:
            break
        default:
            break
        }
        if case .drag(.moved, let point) = gesture {
            let delta = TrackpadAcceleration.apply(dx: point.x, dy: point.y, precision: features.precisionMode)
            let content = contentSize()
            guard content.width > 0, content.height > 0 else { return }
            let moved = trackpad.apply(normalizedDelta: XAPoint(x: delta.x / content.width, y: delta.y / content.height))
            input.send(intent: .mouse(phase: .move, button: .left, x: moved.x, y: moved.y, space: .absoluteNormalized))
            cursorNorm = CGPoint(x: moved.x, y: moved.y)
            cursorVisible = true
            layoutCursor()
        } else if case .tap = gesture {
            input.send(intent: .mouse(phase: .down, button: .left, x: trackpad.normalized.x, y: trackpad.normalized.y, space: .absoluteNormalized))
            input.send(intent: .mouse(phase: .up, button: .left, x: trackpad.normalized.x, y: trackpad.normalized.y, space: .absoluteNormalized))
        } else if case .longPress = gesture {
            input.send(intent: .mouse(phase: .down, button: .right, x: trackpad.normalized.x, y: trackpad.normalized.y, space: .absoluteNormalized))
            input.send(intent: .mouse(phase: .up, button: .right, x: trackpad.normalized.x, y: trackpad.normalized.y, space: .absoluteNormalized))
        } else {
            for intent in GestureMapper.intents(for: gesture) { input.send(intent: intent) }
        }
    }

    private func forwardLegacy(_ gesture: FingerGesture) {
        switch gesture {
        case .tap(let point), .longPress(let point):
            receiver.sendTouch(phase: "began", x: point.x, y: point.y)
            receiver.sendTouch(phase: "ended", x: point.x, y: point.y)
        case .drag(let phase, let point):
            let name: String
            switch phase {
            case .began: name = "began"
            case .moved: name = "moved"
            case .ended: name = "ended"
            }
            receiver.sendTouch(phase: name, x: point.x, y: point.y)
        case .scroll(let dx, let dy, _):
            receiver.sendScroll(dx: dx, dy: dy)
        default:
            break
        }
    }

    private func normalize(_ location: XAPoint) -> XAPoint? {
        let rotation: XARotation
        switch features.inputRotation {
        case 90: rotation = .clockwise90
        case 180: rotation = .clockwise180
        case 270: rotation = .clockwise270
        default: rotation = .identity
        }
        let video = videoSize == .zero ? XASize(width: 1440, height: 1080) : XASize(width: Double(videoSize.width), height: Double(videoSize.height))
        return CoordinateMapper.normalize(MapRequest(
            point: location,
            pointSpace: .viewPoints,
            viewSizePoints: XASize(width: Double(videoView.bounds.width), height: Double(videoView.bounds.height)),
            pixelsPerPoint: Double(UIScreen.main.scale),
            videoPixelSize: video,
            rotation: rotation
        ))
    }

    private func contentSize() -> XASize {
        let rect = CoordinateMapper.contentRect(
            view: XASize(width: Double(videoView.bounds.width), height: Double(videoView.bounds.height)),
            video: XASize(width: Double(max(videoSize.width, 1)), height: Double(max(videoSize.height, 1)))
        )
        return rect.size
    }

    private func addGestures() {
        let scroll = UIPanGestureRecognizer(target: self, action: #selector(scrollPan(_:)))
        scroll.minimumNumberOfTouches = 2
        scroll.maximumNumberOfTouches = 2
        view.addGestureRecognizer(scroll)
        let three = UIPanGestureRecognizer(target: self, action: #selector(threePan(_:)))
        three.minimumNumberOfTouches = 3
        three.maximumNumberOfTouches = 3
        view.addGestureRecognizer(three)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        view.addGestureRecognizer(pinch)
        let twoTap = UITapGestureRecognizer(target: self, action: #selector(twoTap))
        twoTap.numberOfTouchesRequired = 2
        view.addGestureRecognizer(twoTap)
        let twoHold = UILongPressGestureRecognizer(target: self, action: #selector(twoHold(_:)))
        twoHold.numberOfTouchesRequired = 2
        twoHold.minimumPressDuration = 0.35
        view.addGestureRecognizer(twoHold)
        let edge = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(edgePan(_:)))
        edge.edges = features.gestureTuning.sidebarOnLeft ? .left : .right
        view.addGestureRecognizer(edge)
    }

    @objc private func scrollPan(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .changed || gesture.state == .ended else { return }
        let translation = gesture.translation(in: videoView)
        gesture.setTranslation(.zero, in: videoView)
        let gain = features.gestureTuning.clamped().scrollGain
        let pixels = CoordinateMapper.scrollPixels(
            viewDelta: XAPoint(x: Double(translation.x) * gain, y: Double(translation.y) * gain),
            contentSize: contentSize(),
            videoPixelSize: XASize(width: Double(max(videoSize.width, 1)), height: Double(max(videoSize.height, 1)))
        )
        let sendInertia = gesture.state == .ended && features.scrollInertia
        input.send(intent: .scroll(dx: pixels.x, dy: pixels.y, inertia: false))
        receiver.sendScroll(dx: pixels.x, dy: pixels.y)
        if sendInertia {
            let velocity = gesture.velocity(in: videoView)
            for step in ScrollInertia.steps(velocityX: Double(velocity.x) * 0.016 * gain, velocityY: Double(velocity.y) * 0.016 * gain) {
                let extra = CoordinateMapper.scrollPixels(viewDelta: XAPoint(x: step.dx, y: step.dy), contentSize: contentSize(), videoPixelSize: XASize(width: Double(max(videoSize.width, 1)), height: Double(max(videoSize.height, 1))))
                input.send(intent: .scroll(dx: extra.x, dy: extra.y, inertia: true))
                receiver.sendScroll(dx: extra.x, dy: extra.y)
            }
        }
    }

    @objc private func threePan(_ gesture: UIPanGestureRecognizer) {
        guard features.threeFingerShortcuts, gesture.state == .ended else { return }
        let translation = gesture.translation(in: view)
        guard let action = ThreeFingerMapper.action(dx: Double(translation.x), dy: Double(translation.y)) else { return }
        for intent in ThreeFingerMapper.intents(for: action) { input.send(intent: intent) }
    }

    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        guard features.pinchMagnifier, gesture.state == .changed || gesture.state == .ended else { return }
        let point = gesture.location(in: videoView)
        let around = normalize(XAPoint(x: Double(point.x), y: Double(point.y))) ?? XAPoint(x: 0.5, y: 0.5)
        magnifier.pinch(by: Double(gesture.scale), around: around)
        gesture.scale = 1
        applyMagnifier()
    }

    @objc private func twoTap() {
        let point = cursorNorm
        let gesture = FingerGesture.twoFingerTap(XAPoint(x: Double(point.x), y: Double(point.y)))
        for intent in GestureMapper.intents(for: gesture) { input.send(intent: intent) }
    }

    @objc private func twoHold(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: videoView)
        let normalized = normalize(XAPoint(x: Double(point.x), y: Double(point.y))) ?? XAPoint(x: 0.5, y: 0.5)
        for intent in GestureMapper.intents(for: .twoFingerLongPress(normalized)) { input.send(intent: intent) }
    }

    @objc private func edgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard features.touchscreenGestures, gesture.state == .ended else { return }
        let start = gesture.location(in: view)
        if TouchGestureRouter.edgeDrawer(
            enabled: true,
            startX: Double(start.x),
            viewWidth: Double(view.bounds.width),
            translationX: Double(gesture.translation(in: view).x),
            sidebarOnLeft: features.gestureTuning.sidebarOnLeft
        ) {
            collapsed = false
            applyChrome()
        }
    }

    private func wireSidebar() {
        sidebar.onToggle = { [weak self] mask in
            guard let self = self else { return }
            let down = !self.heldModifiers.contains(mask)
            if down { self.heldModifiers.insert(mask) } else { self.heldModifiers.remove(mask) }
            self.sidebar.setModifier(mask, on: down)
            self.input.send(intent: .modifier(mask, down: down))
        }
        sidebar.onEsc = { [weak self] in self?.sendShortcut(KeyShortcut(input: "\u{1b}", modifiers: [])) }
        sidebar.onUndo = { [weak self] in self?.sendShortcut(KeyShortcut(input: "z", modifiers: .command)) }
        sidebar.onRedo = { [weak self] in self?.sendShortcut(KeyShortcut(input: "z", modifiers: [.command, .shift])) }
        sidebar.onKeyboard = { [weak self] in self?.toggleKeyboard() }
        sidebar.onDisconnect = { [weak self] in self?.userDisconnect() }
        sidebar.onSettings = { [weak self] in self?.showSettings() }
        sidebar.onPrecision = { [weak self] in
            guard let self = self else { return }
            self.features.precisionMode.toggle()
            self.precisionLabel.isHidden = !self.features.precisionMode
            LocalSettings.save(token: self.token, features: self.features)
        }
        sidebar.onTrackpad = { [weak self] in
            guard let self = self else { return }
            self.features.trackpadMode.toggle()
            LocalSettings.save(token: self.token, features: self.features)
            self.statusLabel.text = self.features.trackpadMode ? "Trackpad mode sends pointer moves" : self.statusLabel.text
        }
        sidebar.onCollapse = { [weak self] in
            self?.collapsed.toggle()
            self?.applyChrome()
        }
    }

    private func command(_ item: CommandStripItem) {
        guard features.commandStrip else { return }
        if let action = item.windowAction {
            guard features.windowSnapping || features.touchscreenGestures else { return }
            input.sendWindow(action)
            return
        }
        sendShortcut(KeyShortcut(input: item.input, modifiers: XAModifierMask(rawValue: item.modifiers)))
    }

    private func sendShortcut(_ shortcut: KeyShortcut) {
        for intent in shortcut.intents() { input.send(intent: intent) }
    }

    private func sendSnap(_ zone: SnapZone) {
        guard features.windowSnapping || features.touchscreenGestures else { return }
        switch zone {
        case .leftHalf: input.sendWindow(.snapLeft)
        case .rightHalf: input.sendWindow(.snapRight)
        case .full: input.sendWindow(.fill)
        case .mainDisplay: input.sendWindow(.moveToMain)
        }
    }

    private func toggleKeyboard() {
        keyboardOn.toggle()
        if keyboardOn { keyInput.becomeFirstResponder() } else { keyInput.resignFirstResponder(); becomeFirstResponder() }
    }

    private func userDisconnect() {
        userPaused = true
        input.sendRelease()
        input.pause()
        receiver.pause()
        UIApplication.shared.isIdleTimerDisabled = false
        releaseModifiers()
        statusLabel.text = "Disconnected"
        statusLabel.isHidden = false
    }

    private func showSettings() {
        let settings = SettingsViewController(features: features, token: token)
        settings.onChange = { [weak self] features, token in
            guard let self = self else { return }
            self.features = features
            self.token = token
            self.input.token = token
            self.input.requirePairing = features.requirePairing
            self.clipboard.enabled = features.clipboardSync
            self.precisionLabel.isHidden = !features.precisionMode
            if features.audio { self.audio.start() } else { self.audio.stop() }
            LocalSettings.save(token: token, features: features)
            self.applyChrome()
            self.interpreter = DirectTouchInterpreter(
                slop: features.gestureTuning.clamped().slop,
                doubleTapWindow: features.gestureTuning.clamped().doubleTapWindow,
                longPressDuration: features.gestureTuning.clamped().longPressDuration
            )
        }
        let nav = UINavigationController(rootViewController: settings)
        present(nav, animated: true)
    }

    private func applyChrome() {
        sidebarWidth.constant = collapsed ? 36 : 168
        sidebar.setCollapsed(collapsed)
        sidebarLeading.isActive = features.gestureTuning.sidebarOnLeft
        sidebarTrailing.isActive = !features.gestureTuning.sidebarOnLeft
        commandStrip.isHidden = !features.commandStrip
        statsLabel.isHidden = !features.showStats
        precisionLabel.isHidden = !features.precisionMode
    }

    private func applyMagnifier() {
        guard features.pinchMagnifier, magnifier.scale > 1.01 else {
            videoView.transform = .identity
            return
        }
        let scale = CGFloat(magnifier.scale)
        let tx = CGFloat(0.5 - magnifier.center.x) * videoView.bounds.width
        let ty = CGFloat(0.5 - magnifier.center.y) * videoView.bounds.height
        videoView.transform = CGAffineTransform(translationX: tx, y: ty).scaledBy(x: scale, y: scale)
    }

    private func layoutCursor() {
        let rect = videoView.bounds
        cursorLayer.position = CGPoint(x: rect.minX + cursorNorm.x * rect.width, y: rect.minY + cursorNorm.y * rect.height)
        cursorLayer.isHidden = !cursorVisible
    }

    private func releaseModifiers() {
        for bit in heldModifiers.individualBits {
            input.send(intent: .modifier(bit, down: false))
            sidebar.setModifier(bit, on: false)
        }
        heldModifiers = []
    }

    private func publishHealth() {
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
        warningLabel.isHidden = thermal != .serious && thermal != .critical
        warningLabel.text = thermal == .critical ? "Very warm. The Mac should drop quality." : "Warm. Quality may step down."
        receiver.sendHealth(HealthReport(
            thermal: thermal,
            batteryFraction: level < 0 ? nil : Double(level),
            batteryState: state,
            fpsDelivered: fps,
            decodeFails: 0
        ))
        refreshStats()
    }

    private func refreshStats() {
        let pipeline = pipelineMs.map { String(format: "%.0f ms", $0) } ?? "—"
        let rtt = rttMs.map { String(format: "%.0f ms", $0) } ?? "—"
        statsLabel.text = "  FPS \(String(format: "%.0f", fps)) delivered\n  Handoff \(String(format: "%.1f", handoffMs)) ms\n  Capture→ack \(pipeline)\n  Input RTT \(rtt)\n  \(streamLabel)  "
    }

    @objc private func foreground() {
        guard !userPaused else { return }
        receiver.ensureListening()
        input.ensureListening()
    }

    @objc private func backgrounded() {
        input.sendRelease()
        releaseModifiers()
        UIApplication.shared.isIdleTimerDisabled = false
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask {
            UIApplication.shared.endBackgroundTask(task)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            UIApplication.shared.endBackgroundTask(task)
        }
    }

    private func modifiers(from flags: UIKeyModifierFlags) -> XAModifierMask {
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
        UIApplication.shared.isIdleTimerDisabled = connected
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
        }
    }
    func videoReceiver(_ receiver: VideoReceiver, videoSizeDidChange size: CGSize) {
        videoSize = size
        streamLabel = "\(Int(size.width))×\(Int(size.height))"
        refreshStats()
    }
    func videoReceiver(_ receiver: VideoReceiver, cursor point: CGPoint, visible: Bool) {
        guard !features.trackpadMode else { return }
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
    func videoReceiverBecameXAHost(_ receiver: VideoReceiver) { xaHost = true }
    func videoReceiver(_ receiver: VideoReceiver, stream: StreamAnnouncement) {
        streamLabel = "\(stream.preset) \(stream.width)×\(stream.height)@\(stream.fps)"
        if stream.experimental { streamLabel += " experimental" }
        refreshStats()
    }
    func videoReceiver(_ receiver: VideoReceiver, metrics: XAMetrics) {
        pipelineMs = metrics.captureToAckMs
        refreshStats()
    }
    func inputChannel(_ channel: InputChannel, armed: Bool, reason: String) {
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
        self.audio.enqueue(audio.pcm)
    }
    func inputChannel(_ channel: InputChannel, roundTripMs: Double) {
        rttMs = roundTripMs
        refreshStats()
    }
}
