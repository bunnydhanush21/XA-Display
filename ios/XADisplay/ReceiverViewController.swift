import AVFoundation
import UIKit
import XADisplayProtocol

final class ReceiverViewController: UIViewController, VideoReceiverDelegate, InputChannelDelegate {
    let videoView = VideoContainerView()
    let sidebar = SidebarView()
    let commandStrip = CommandStripView()
    let statsLabel = StatsOverlay()
    let statusLabel = UILabel()
    let warningLabel = UILabel()
    let precisionLabel = UILabel()
    let keyInput = KeyInputView()
    var receiver: VideoReceiver!
    let input = InputChannel()
    let clipboard = ClipboardBridge()
    let audio = RoutedAudioPlayer()
    var features = XAFeatureSettings()
    var token = ""
    var interpreter = DirectTouchInterpreter()
    var magnifier = Magnifier()
    var videoSize = CGSize.zero
    var cursorNorm = CGPoint(x: 0.5, y: 0.5)
    var cursorVisible = false
    let cursorLayer = CALayer()
    var heldModifiers = XAModifierMask()
    var sidebarWidth: NSLayoutConstraint!
    var sidebarLeading: NSLayoutConstraint!
    var sidebarTrailing: NSLayoutConstraint!
    var collapsed = false
    var keyboardOn = false
    var trackpad = TrackpadCursor()
    var streamLabel = "waiting"
    var handoffMs = 0.0
    var pipelineMs: Double?
    var rttMs: Double?
    var latestMetrics = PadStreamSample(
        receivedFramesPerSecond: 0, displayedFramesPerSecond: 0, droppedFrames: 0, inboundBitsPerSecond: 0, decodeTimeMilliseconds: 0, endToEndLatencyMilliseconds: nil, inputRoundTripMilliseconds: nil
    )
    var metricRows: [PadStreamSample] = []
    var fps = 0.0
    var userPaused = false
    var lastMove = XAPoint.zero
    var lastMoveTime = 0.0
    var xaHost = false
    var healthTimer: Timer?
    let chrome = TouchChromeController()
    var assist = TouchAssist()
    var titleArbiter = TitleBarArbiter()
    var titleTimer: Timer?
    var windowFrames: [XARect] = []
    var menuTitles: [String] = []
    var frontBundle = ""
    var resizing: (index: Int, corner: ResizeCorner)?
    var resizeOrigin: XAPoint?
    var dragOriginView: XAPoint?
    var dragOriginTime = 0.0
    var lastRepeatTime: Double?
    var loupeImage: UIImage?
    var sidebarEdge: UIScreenEdgePanGestureRecognizer?
    var drawerEdge: UIScreenEdgePanGestureRecognizer?
    var commandStripHeight: NSLayoutConstraint!
    let macBrowser = MacBrowser()
    let batteryLoop = BatteryCareLoop()
    var chargeConfig = ChargeLimitConfig()
    var settingsDocument = XASettingsDocument.defaults
    var localCursor = false
    var keepalive: Timer?
    var scrollRecognizer: UIPanGestureRecognizer?
    var directory = MacDirectory()
    var discoveredMacs: [String] = []
    var mediaPanel: MediaRemoteViewController?
    var orientDebounce = OrientationDebounce()
    var orientTimer: Timer?
    var letterboxFallback = false
    var streamTransform = CGAffineTransform.identity
    var layingVideo = false
    let padSession = PadSession()
    let connectionOverlay = ConnectionOverlay()
    let pill = UILabel()
    var pillTimer: Timer?
    var inBackground = false
    var pendingPointer: (() -> Void)?
    var pointerLink: CADisplayLink?

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        assist.edgeDrawer ? .right : []
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let loaded = LocalSettings.load()
        token = loaded.token
        features = loaded.features
        assist = LocalSettings.loadAssist()
        directory = LocalSettings.loadMacs()
        settingsDocument = LocalSettings.loadDocument(features: features, assist: assist)
        features = settingsDocument.features
        assist = settingsDocument.assist
        chargeConfig = settingsDocument.charge
        applyLaunchRoute()
        interpreter = DirectTouchInterpreter(
            slop: features.gestureTuning.clamped().slop,
            doubleTapWindow: features.gestureTuning.clamped().doubleTapWindow,
            longPressDuration: features.gestureTuning.clamped().longPressDuration
        )
        videoView.translatesAutoresizingMaskIntoConstraints = true
        videoView.autoresizingMask = []
        videoView.isUserInteractionEnabled = false
        view.addSubview(videoView)
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
            sidebarLeading
        ])
        wireSidebar()

        commandStrip.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(commandStrip)
        NSLayoutConstraint.activate([
            commandStrip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            commandStrip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            commandStrip.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        commandStripHeight = commandStrip.heightAnchor.constraint(equalToConstant: 52)
        commandStripHeight.isActive = true
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
            precisionLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
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
        receiver.legacyTokenSeal = features.legacyTokenSeal
        receiver.onSessionKeys = { [weak self] keys, connectionID in
            self?.input.installSession(keys, connectionID: connectionID)
        }
        input.legacyTokenSeal = features.legacyTokenSeal
        input.delegate = self
        adoptToken(token)
        input.requirePairing = features.requirePairing
        input.deviceName = UIDevice.current.name
        clipboard.enabled = features.clipboardSync
        clipboard.onLocalCopy = { [weak self] text in
            guard let self = self, self.features.clipboardSync else { return }
            self.input.sendClipboard(text: text, revision: UInt64(UIPasteboard.general.changeCount))
        }
        clipboard.start()
        macBrowser.onNames = { [weak self] names in
            self?.discoveredMacs = names
        }
        if features.oneTapReconnect || features.rememberMacs { macBrowser.start() }
        chrome.install(in: view)
        wireChrome()
        addGestures()
        applyChrome()
        installConnectionChrome()
        receiver.start()
        input.start()
        scheduleMaintenance()
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

    @objc func hardwareKey(_ command: UIKeyCommand) {
        let mask = modifiers(from: command.modifierFlags)
        let shortcut = KeyShortcut(input: command.input ?? "", modifiers: mask)
        for intent in shortcut.intents() { input.send(intent: intent) }
    }

    var didOfferPicker = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didOfferPicker else { return }
        if !UserDefaults.standard.bool(forKey: "XADisplay.didOnboard") {
            didOfferPicker = true
            let cards = FirstRunController()
            cards.modalPresentationStyle = .fullScreen
            cards.onFinish = { [weak self] in self?.showMacPicker() }
            present(cards, animated: false)
            return
        }
        if case .picker = LaunchRoute.decide(oneTap: features.oneTapReconnect, directory: directory) {
            didOfferPicker = true
            showMacPicker()
        }
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
        layoutVideo()
        noteOrientation(portrait ? "portrait" : "landscape")
        layoutCursor()
        applyChrome()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { feed(touches, .began, event) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { feed(touches, .moved, event) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { feed(touches, .ended, event) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        feed(touches, .cancelled, event)
        chrome.loupe.hide()
        resizing = nil
    }

    func feed(_ touches: Set<UITouch>, _ phase: TouchSample.Phase, _ event: UIEvent?) {
        guard let touch = touches.first else { return }
        let count = event?.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled }.count ?? 1
        let raw = touch.location(in: videoView)
        let point = CGPoint(x: raw.x + CGFloat(assist.cursorOffsetX), y: raw.y + CGFloat(assist.cursorOffsetY))
        if phase == .began {
            dragOriginView = XAPoint(x: Double(raw.x), y: Double(raw.y))
            resizeOrigin = XAPoint(x: Double(point.x), y: Double(point.y))
            dragOriginTime = touch.timestamp
            loupeImage = nil
            resizing = resizeHit(at: raw)
        }
        if features.lowLatencyWiFi, !features.trackpadMode, let predicted = normalize(XAPoint(x: Double(point.x), y: Double(point.y))) {
            cursorNorm = CGPoint(x: predicted.x, y: predicted.y)
            cursorVisible = true
            localCursor = phase != .ended && phase != .cancelled
            layoutCursor()
        }
        let sample = TouchSample(time: touch.timestamp, phase: phase, location: XAPoint(x: Double(point.x), y: Double(point.y)), activeTouches: count)
        let gestures = interpreter.feed(sample) { [weak self] location in
            self?.normalize(location)
        }
        for gesture in gestures { perform(gesture, finger: raw, pointer: point, time: touch.timestamp) }
        if phase == .moved || phase == .ended {
            lastMove = XAPoint(x: Double(point.x), y: Double(point.y))
            lastMoveTime = touch.timestamp
        }
        if phase == .ended || phase == .cancelled {
            chrome.loupe.hide()
            if phase == .cancelled { resizing = nil }
        }
    }

}
