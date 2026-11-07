import AppKit
import ApplicationServices
import Darwin
import Foundation
import Network

final class HostController {
    var onState: ((String) -> Void)?
    private let poster = EventPoster()
    private let capture = CapturePipeline()
    private let display = XAVirtualDisplay()
    private var dispatcher: InputDispatcher
    private var settings: XAFeatureSettings
    private var token: String
    private var library: PresetLibrary
    private var adaptation: AdaptationController
    private var preset: StreamPreset
    private var portrait = false
    private var transport: TransportKind = .none
    private var videoParser = FrameParser(limits: .video)
    private var inputParser = FrameParser(limits: .input)
    private var usbFD: FDStream?
    private var wifiVideo: NWConnection?
    private var wifiInput: NWConnection?
    private var inputFD: FDStream?
    private var browser: NWBrowser?
    private var wifiHost: String?
    private var timer: Timer?
    private var lastDisplayFrame = XARect(x: 0, y: 0, width: 0, height: 0)
    private var savedDisplayID: CGDirectDisplayID = 0
    private var pendingSends = 0
    private var sendBudget = SendBudget()
    private var clipboardRevision: UInt64 = 0
    private var pasteboardCount = NSPasteboard.general.changeCount
    private var logs: [String] = []
    private var running = false
    private let queue = DispatchQueue(label: "xa.host")

    init() {
        let stored = HostStore.load()
        settings = stored.settings
        token = stored.token
        library = PresetLibrary(enabled: settings.savedPresets, items: stored.presets)
        if settings.savedPresets, let first = library.items.last {
            preset = StreamPreset.preset(first.preset).oriented(portrait: first.portrait)
            portrait = first.portrait
        } else {
            preset = .balanced
        }
        adaptation = AdaptationController(preset: preset.id, usb: true)
        dispatcher = InputDispatcher(
            expectedToken: token,
            requirePairing: settings.requirePairing,
            clipboardEnabled: settings.clipboardSync,
            windowActionsEnabled: settings.windowSnapping || settings.touchscreenGestures
        )
        dispatcher.sessionGenerator = {
            var value: UInt32 = 0
            arc4random_buf(&value, MemoryLayout<UInt32>.size)
            return value == 0 ? 1 : value
        }
    }

    func start() {
        running = true
        log("XA Display Host started")
        startBrowser()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.pollClipboard()
            self?.queue.async { self?.tick() }
        }
        queue.async { self.tick() }
        publish()
    }

    func stop() {
        running = false
        timer?.invalidate()
        let main = WindowMover.mainDisplayFrame()
        if lastDisplayFrame.width > 0 {
            let moved = WindowMover.recover(from: lastDisplayFrame, to: main)
            log("Recovered \(moved) window(s) onto the main display")
        }
        capture.stop()
        display.stop()
        closeLinks()
        publish()
    }

    func currentToken() -> String { token }

    func regenerateToken() {
        token = PairingToken.make()
        dispatcher.expectedToken = token
        dispatcher.requirePairing = settings.requirePairing
        HostStore.save(token: token, settings: settings, presets: library.items)
        log("Pairing token regenerated")
        publish()
    }

    func setRequirePairing(_ on: Bool) {
        settings.requirePairing = on
        dispatcher.requirePairing = on
        persist()
    }

    func setClipboard(_ on: Bool) {
        settings.clipboardSync = on
        dispatcher.clipboardEnabled = on
        persist()
    }

    func setAudio(_ on: Bool) {
        settings.audio = on
        persist()
        restartCaptureIfNeeded()
    }

    func setWindowSnapping(_ on: Bool) {
        settings.windowSnapping = on
        dispatcher.windowActionsEnabled = on || settings.touchscreenGestures
        persist()
    }

    func setTouchGestures(_ on: Bool) {
        settings.touchscreenGestures = on
        dispatcher.windowActionsEnabled = settings.windowSnapping || on
        persist()
    }

    func setWiFi(_ on: Bool) {
        settings.wifiFallback = on
        persist()
    }

    func setAutoConnect(_ on: Bool) {
        settings.autoConnectUSB = on
        persist()
        if on { tick() }
    }

    func setSavedPresets(_ on: Bool) {
        settings.savedPresets = on
        library.enabled = on
        persist()
    }

    func selectPreset(_ id: StreamPreset.ID) {
        preset = StreamPreset.preset(id).oriented(portrait: portrait)
        adaptation = AdaptationController(preset: id, usb: transport != .wifi)
        if settings.savedPresets {
            library.save(SavedDisplayPreset(name: "Last", preset: id, portrait: portrait))
        }
        persist()
        rebuildDisplay()
    }

    func saveNamedPreset(_ name: String) {
        guard settings.savedPresets else { return }
        library.save(SavedDisplayPreset(name: name, preset: preset.id, portrait: portrait))
        persist()
    }

    func diagnostics() -> String {
        DiagnosticsText.render(DiagnosticsSnapshot(
            appVersion: "1.0.0",
            transport: transport.rawValue,
            preset: "\(preset.id.rawValue) \(preset.width)x\(preset.height)@\(adaptation.fps)",
            permissions: [
                "screenRecording": CGPreflightScreenCaptureAccess(),
                "accessibility": AXIsProcessTrusted(),
            ],
            pairingToken: token,
            thermal: "mac",
            battery: "mac",
            notes: logs.suffix(12).map { $0 }
        ))
    }

    func settingsSnapshot() -> XAFeatureSettings { settings }

    private func tick() {
        guard running, settings.autoConnectUSB || transport != .none else { return }
        let usb = !UsbmuxClient.listUSBDevices().isEmpty
        let desired = LinkPreference.desired(usbAvailable: usb, wifiAvailable: wifiHost != nil, wifiAllowed: settings.wifiFallback)
        if LinkPreference.shouldSwitch(current: transport, desired: desired) || (transport == .none && desired != .none) {
            connect(desired)
        }
        adapt(dt: 1.5)
    }

    private func connect(_ kind: TransportKind) {
        apply(dispatcher.disconnect())
        closeLinks()
        transport = kind
        guard kind != .none else { publish(); return }
        log("Connecting over \(kind.rawValue)")
        if kind == .usb {
            guard let device = UsbmuxClient.listUSBDevices().first,
                  let video = UsbmuxClient.connect(deviceID: device.deviceID, port: XADisplayProtocolInfo.videoPort) else {
                transport = .none
                publish()
                return
            }
            let stream = FDStream(fd: video)
            stream.onData = { [weak self] data in self?.queue.async { self?.ingestVideo(data) } }
            stream.onClose = { [weak self] in self?.queue.async { self?.linkClosed() } }
            usbFD = stream
            if let input = UsbmuxClient.connect(deviceID: device.deviceID, port: XADisplayProtocolInfo.inputPort) {
                let inputStream = FDStream(fd: input)
                inputStream.onData = { [weak self] data in self?.queue.async { self?.ingestInput(data) } }
                inputStream.onClose = { [weak self] in self?.queue.async { self?.releaseInput(reason: "input closed") } }
                inputFD = inputStream
            }
            sendControl(.xaHello, onVideo: true)
        } else if let host = wifiHost {
            openNW(host: host, port: XADisplayProtocolInfo.videoPort, video: true)
            openNW(host: host, port: XADisplayProtocolInfo.inputPort, video: false)
            sendControl(.xaHello, onVideo: true)
        }
        adaptation = AdaptationController(preset: preset.id, usb: kind == .usb)
        publish()
    }

    private func openNW(host: String, port: UInt16, video: Bool) {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: NWParameters(tls: nil, tcp: tcp))
        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state, video {
                self?.sendControl(.xaHello, onVideo: true)
            }
            if case .failed = state { self?.linkClosed() }
        }
        connection.start(queue: queue)
        receiveNW(connection, video: video)
        if video { wifiVideo = connection } else { wifiInput = connection }
    }

    private func receiveNW(_ connection: NWConnection, video: Bool) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            if let data = data {
                if video { self?.ingestVideo(data) } else { self?.ingestInput(data) }
            }
            if error != nil || isComplete { return }
            self?.receiveNW(connection, video: video)
        }
    }

    private func ingestVideo(_ data: Data) {
        switch videoParser.append(data, now: Date().timeIntervalSince1970) {
        case .ok(let frames):
            for frame in frames { handleVideo(frame) }
        case .failed:
            log("Video frame rejected")
            linkClosed()
        }
    }

    private func ingestInput(_ data: Data) {
        switch inputParser.append(data, now: Date().timeIntervalSince1970) {
        case .ok(let frames):
            for frame in frames {
                do {
                    if let message = try XAInputMessage.decode(frame) {
                        handleInput(message)
                    }
                } catch {
                    linkClosed()
                    return
                }
            }
        case .failed:
            log("Input frame rejected")
            releaseInput(reason: "malformed input")
        }
    }

    private func handleVideo(_ payload: Data) {
        guard PayloadKind.classify(payload) == .controlJSON else { return }
        switch VideoControlMessage.parse(payload) {
        case .hello(let hello):
            portrait = hello.orientation == "portrait" || hello.pixelsHigh > hello.pixelsWide
            preset = StreamPreset.preset(preset.id).oriented(portrait: portrait)
            rebuildDisplay()
        case .frameAck(let ack):
            let now = Date().timeIntervalSince1970 * 1000
            if let ms = LatencyMath.captureToAck(captureMs: ack.captureMs, ackMs: now) {
                sendControl(.xaMetrics(XAMetrics(captureToAckMs: ms, encodeMs: nil)), onVideo: true)
            }
        case .health(let health):
            queue.async { [weak self] in
                self?.lastHealth = health
            }
        case .decodeFailed:
            if let next = PresetFallback.afterDecodeFailure(preset.id) {
                log("Decode failed. Falling back from \(preset.id.rawValue) to \(next.rawValue)")
                selectPreset(next)
            }
        case .touch, .scroll:
            if LegacyInputPolicy.acceptsUnauthenticatedVideoInput {
                log("ignored unauthenticated video input")
            }
        default:
            break
        }
    }

    private var lastHealth = HealthReport(thermal: .unknown, batteryFraction: nil, batteryState: "unknown", fpsDelivered: 0, decodeFails: 0)

    private func handleInput(_ message: XAInputMessage) {
        let outcome = dispatcher.handle(message, hostNowMs: Date().timeIntervalSince1970 * 1000)
        apply(outcome)
    }

    private func apply(_ outcome: DispatchOutcome) {
        switch outcome {
        case .post(let events):
            apply(events)
        case .reply(let message):
            sendInput(message)
        case .postAndReply(let events, let message):
            apply(events)
            sendInput(message)
        case .drop:
            break
        }
    }

    private func apply(_ events: [PostedEvent]) {
        for event in events {
            switch event {
            case .clipboard(let text, let revision):
                guard settings.clipboardSync, ClipboardPolicy.accept(enabled: true, armed: true, utf8Count: text.utf8.count) else { continue }
                clipboardRevision = revision
                pasteboardCount = NSPasteboard.general.changeCount + 1
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            case .window(let action):
                guard settings.windowSnapping || settings.touchscreenGestures else { continue }
                let zone: SnapZone
                switch action {
                case .snapLeft: zone = .leftHalf
                case .snapRight: zone = .rightHalf
                case .fill, .snapFull: zone = .full
                case .moveToMain: zone = .mainDisplay
                case .moveToVirtual: zone = .full
                }
                _ = WindowMover.apply(zone: zone, virtual: lastDisplayFrame, main: WindowMover.mainDisplayFrame())
            default:
                poster.post(event)
            }
        }
    }

    private func rebuildDisplay() {
        let pixelsWide = preset.width
        let pixelsHigh = preset.height
        let scale = preset.id == .native ? 2.0 : 1.0
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let ok = self.display.applyPixelWidth(UInt32(pixelsWide), height: UInt32(pixelsHigh), scale: scale, name: "XA Display")
            guard ok, self.display.displayID != 0 else {
                self.log("Virtual display unavailable")
                self.publish()
                return
            }
            self.savedDisplayID = self.display.displayID
            self.lastDisplayFrame = WindowMover.displayFrame(self.display.displayID)
            self.dispatcher.displayFrame = self.lastDisplayFrame
            self.dispatcher.videoPixelSize = XASize(width: Double(pixelsWide), height: Double(pixelsHigh))
            self.restartCaptureIfNeeded()
            let announcement = StreamAnnouncement(
                preset: self.preset.id.rawValue,
                width: pixelsWide,
                height: pixelsHigh,
                fps: self.adaptation.fps,
                bitrate: self.adaptation.bitrate,
                experimental: self.preset.experimental
            )
            self.sendControl(.xaStream(announcement), onVideo: true)
            self.publish()
        }
    }

    private func restartCaptureIfNeeded() {
        guard savedDisplayID != 0, CGPreflightScreenCaptureAccess() else { return }
        capture.stop()
        let width = preset.width
        let height = preset.height
        let fps = adaptation.fps
        let bitrate = adaptation.bitrate
        let level = preset.profileLevelName
        let audio = settings.audio
        let displayID = savedDisplayID
        Task { [weak self] in
            do {
                try await self?.capture.start(displayID: displayID, width: width, height: height, fps: fps, bitrate: bitrate, profileLevel: level, audio: audio)
                self?.capture.onAccessUnit = { data, key, _, captureMs, encodeMs in
                    self?.sendVideo(data, keyframe: key, captureMs: captureMs, encodeMs: encodeMs)
                }
                self?.capture.onPCM = { pcm in
                    self?.sendAudio(pcm)
                }
                self?.log("Capture \(width)x\(height) @ \(fps) \(level)")
            } catch {
                self?.log("Capture failed: \(error.localizedDescription)")
                if self?.preset.id == .native {
                    self?.selectPreset(.balanced)
                }
            }
        }
    }

    private func sendVideo(_ annex: Data, keyframe: Bool, captureMs: Double, encodeMs: Double) {
        let decision = sendBudget.admit(pending: pendingSends, isKeyframe: keyframe)
        guard decision == .send else { return }
        guard annex.count <= FrameLimits.video.maxPayload else { return }
        pendingSends += 1
        let frame = LengthPrefixedFraming.encode(annex)
        sendRaw(frame, video: true) { [weak self] in
            self?.pendingSends = max(0, (self?.pendingSends ?? 1) - 1)
        }
        _ = captureMs
        _ = encodeMs
    }

    private func sendAudio(_ pcm: Data) {
        guard settings.audio, dispatcher.armed else { return }
        guard AudioPolicy.accept(enabled: true, armed: true, byteCount: pcm.count, channels: 2) else { return }
        let message = XAInputMessage.audio(XAAudio(session: dispatcher.session, sampleRate: 48_000, channels: 2, pcm: pcm))
        sendInput(message)
    }

    private func sendControl(_ message: VideoControlMessage, onVideo: Bool) {
        guard let payload = message.jsonData() else { return }
        sendRaw(LengthPrefixedFraming.encode(payload), video: onVideo, done: nil)
    }

    private func sendInput(_ message: XAInputMessage) {
        guard let payload = try? message.encode() else { return }
        sendRaw(LengthPrefixedFraming.encode(payload), video: false, done: nil)
    }

    private func sendRaw(_ data: Data, video: Bool, done: (() -> Void)?) {
        if video, let usbFD = usbFD {
            usbFD.send(data)
            done?()
            return
        }
        if !video, let inputFD = inputFD {
            inputFD.send(data)
            done?()
            return
        }
        let connection = video ? wifiVideo : wifiInput
        connection?.send(content: data, completion: .contentProcessed { _ in done?() })
    }

    private func pollClipboard() {
        guard settings.clipboardSync else { return }
        let board = NSPasteboard.general
        guard board.changeCount != pasteboardCount, let text = board.string(forType: .string) else { return }
        pasteboardCount = board.changeCount
        guard text.utf8.count <= XAClipboard.maxBytes else { return }
        queue.async { [weak self] in
            guard let self = self, self.dispatcher.armed else { return }
            self.clipboardRevision &+= 1
            self.sendInput(.clipboard(XAClipboard(session: self.dispatcher.session, seq: UInt32(truncatingIfNeeded: self.clipboardRevision), revision: self.clipboardRevision, text: text)))
        }
    }

    private func adapt(dt: Double) {
        var signals = AdaptationSignals()
        signals.thermal = lastHealth.thermal
        signals.batteryFraction = lastHealth.batteryFraction
        signals.onExternalPower = lastHealth.batteryState == "charging" || lastHealth.batteryState == "full"
        signals.decodeFailed = false
        signals.sendBacklogFrames = pendingSends
        if let tune = adaptation.advance(dt: dt, signals: signals), tune.bitrate != 0 {
            capture.updateBitrate(tune.bitrate)
            log("Adapt \(tune.reason): \(tune.preset.rawValue) \(tune.fps)fps \(tune.bitrate)bps")
            if tune.preset != preset.id {
                selectPreset(tune.preset)
            }
        }
    }

    private func startBrowser() {
        let browser = NWBrowser(for: .bonjour(type: XADisplayProtocolInfo.bonjourType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let endpoint = results.first?.endpoint else { return }
            if case .service(let name, _, _, _) = endpoint {
                self?.resolve(name: name)
            }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    private func resolve(name: String) {
        let connection = NWConnection(to: .service(name: name, type: XADisplayProtocolInfo.bonjourType, domain: "local", interface: nil), using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state, let path = connection.currentPath, case .hostPort(let host, _) = path.remoteEndpoint {
                self?.wifiHost = "\(host)"
                connection.cancel()
            }
        }
        connection.start(queue: queue)
    }

    private func linkClosed() {
        let events = dispatcher.disconnect()
        apply(events)
        closeLinks()
        transport = .none
        publish()
    }

    private func releaseInput(reason: String) {
        log(reason)
        apply(dispatcher.disconnect())
    }

    private func closeLinks() {
        usbFD?.closeStream()
        usbFD = nil
        inputFD?.closeStream()
        inputFD = nil
        wifiVideo?.cancel()
        wifiInput?.cancel()
        wifiVideo = nil
        wifiInput = nil
        videoParser = FrameParser(limits: .video)
        inputParser = FrameParser(limits: .input)
        pendingSends = 0
    }

    private func persist() {
        HostStore.save(token: token, settings: settings, presets: library.items)
        publish()
    }

    private func publish() {
        let text = "\(transport.rawValue) · \(preset.id.rawValue) \(preset.width)×\(preset.height)"
        DispatchQueue.main.async { self.onState?(text) }
    }

    private func log(_ line: String) {
        logs.append(line)
        if logs.count > 40 { logs.removeFirst(logs.count - 40) }
        NSLog("XADisplayHost %@", line)
    }
}

enum HostStore {
    static let tokenKey = "XADisplayHost.token"
    static let settingsKey = "XADisplayHost.features"
    static let presetsKey = "XADisplayHost.presets"

    static func load() -> (token: String, settings: XAFeatureSettings, presets: [SavedDisplayPreset]) {
        let defaults = UserDefaults.standard
        var token = defaults.string(forKey: tokenKey) ?? ""
        if token.isEmpty {
            token = PairingToken.make()
            defaults.set(token, forKey: tokenKey)
        }
        let settings = defaults.data(forKey: settingsKey).flatMap { try? JSONDecoder().decode(XAFeatureSettings.self, from: $0) } ?? XAFeatureSettings()
        let presets = defaults.data(forKey: presetsKey).flatMap { try? JSONDecoder().decode([SavedDisplayPreset].self, from: $0) } ?? []
        return (token, settings, presets)
    }

    static func save(token: String, settings: XAFeatureSettings, presets: [SavedDisplayPreset]) {
        let defaults = UserDefaults.standard
        defaults.set(token, forKey: tokenKey)
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: settingsKey) }
        if let data = try? JSONEncoder().encode(presets) { defaults.set(data, forKey: presetsKey) }
    }
}
