import AppKit
import ApplicationServices
import Darwin
import Foundation
import Network
import ScreenCaptureKit
import XADisplayProtocol

final class HostController {
    var onState: ((String) -> Void)?
    private let poster = EventPoster()
    private let capture = CapturePipeline()
    private let audioCapture = AudioCapture()
    private var audioMode: AudioRouteMode = HostStore.loadAudioMode()
    private var selectedAudioBundles: [String] = HostStore.loadAudioBundles()
    private var knownAudioApps: [(bundle: String, name: String)] = []
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
    private var wakeListener: NWListener?
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
            windowActionsEnabled: settings.windowSnapping || settings.touchscreenGestures,
            mediaEnabled: settings.mediaRemote
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
        startWakeService()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.pollClipboard()
            self?.publishChrome()
            self?.publishNowPlaying()
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
        audioCapture.stop()
        display.stop()
        wakeListener?.cancel()
        wakeListener = nil
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
        restartAudio()
    }

    func setAudioMode(_ mode: AudioRouteMode) {
        audioMode = mode
        HostStore.saveAudio(mode: mode, bundles: selectedAudioBundles)
        restartAudio()
    }

    func toggleAudioBundle(_ bundle: String) {
        if let index = selectedAudioBundles.firstIndex(of: bundle) {
            selectedAudioBundles.remove(at: index)
        } else {
            selectedAudioBundles.append(bundle)
        }
        HostStore.saveAudio(mode: audioMode, bundles: selectedAudioBundles)
        if audioMode == .selected { restartAudio() }
    }

    func audioMenuState() -> (mode: AudioRouteMode, selected: [String], apps: [(bundle: String, name: String)]) {
        (audioMode, selectedAudioBundles, knownAudioApps)
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
        startWakeService()
    }

    func setOneTapReconnect(_ on: Bool) {
        settings.oneTapReconnect = on
        persist()
        startWakeService()
    }

    func setRememberMacs(_ on: Bool) {
        settings.rememberMacs = on
        persist()
    }

    func setMediaRemote(_ on: Bool) {
        settings.mediaRemote = on
        dispatcher.mediaEnabled = on
        persist()
    }

    func setAutoConnect(_ on: Bool) {
        settings.autoConnectUSB = on
        persist()
        if on { tick() }
    }

    func setLowLatencyWiFi(_ on: Bool) {
        settings.lowLatencyWiFi = on
        persist()
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
        DiagnosticsText.render(
            DiagnosticsSnapshot(
                appVersion: "1.0.0",
                transport: transport.rawValue,
                preset: "\(preset.id.rawValue) \(preset.width)x\(preset.height)@\(adaptation.fps)",
                permissions: [
                    "screenRecording": CGPreflightScreenCaptureAccess(),
                    "accessibility": AXIsProcessTrusted()
                ],
                pairingToken: token,
                thermal: "mac",
                battery: "mac",
                notes: logs.suffix(12).map { $0 }
            ))
    }

    func settingsSnapshot() -> XAFeatureSettings { settings }
    func batterySummary() -> String { lastBatteryText }
    func settingsDocument() -> XASettingsDocument {
        XASettingsDocument(
            features: settings,
            audioVolume: 1,
            audioMode: audioMode.rawValue,
            preset: preset.id.rawValue,
            pairedIDs: pairedIDs
        )
    }

    func applySharedSettings(_ body: String, broadcast: Bool) {
        let current = settingsDocument()
        let merged = SettingsSync.apply(body, to: current)
        if merged.features.requirePairing != current.features.requirePairing { setRequirePairing(merged.features.requirePairing) }
        if merged.features.clipboardSync != current.features.clipboardSync { setClipboard(merged.features.clipboardSync) }
        if merged.features.audio != current.features.audio { setAudio(merged.features.audio) }
        if merged.features.wifiFallback != current.features.wifiFallback { setWiFi(merged.features.wifiFallback) }
        if merged.features.autoConnectUSB != current.features.autoConnectUSB { setAutoConnect(merged.features.autoConnectUSB) }
        if merged.features.lowLatencyWiFi != current.features.lowLatencyWiFi { setLowLatencyWiFi(merged.features.lowLatencyWiFi) }
        if merged.features.windowSnapping != current.features.windowSnapping { setWindowSnapping(merged.features.windowSnapping) }
        if merged.features.mediaRemote != current.features.mediaRemote { setMediaRemote(merged.features.mediaRemote) }
        if merged.audioMode != current.audioMode, let mode = AudioRouteMode(rawValue: merged.audioMode) { setAudioMode(mode) }
        if merged.preset != current.preset, let id = StreamPreset.ID(rawValue: merged.preset) { selectPreset(id) }
        if broadcast { sendControl(.xaSettings(SettingsSync.encode(settingsDocument())), onVideo: true) }
    }

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
        guard kind != .none else {
            publish()
            return
        }
        log("Connecting over \(kind.rawValue)")
        if kind == .usb {
            guard let device = UsbmuxClient.listUSBDevices().first,
                let video = UsbmuxClient.connect(deviceID: device.deviceID, port: XADisplayProtocolInfo.videoPort)
            else {
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
            if settings.lowLatencyWiFi { udpSender.connect(host: host) }
            sendControl(.xaHello, onVideo: true)
        }
        adaptation = AdaptationController(preset: preset.id, usb: kind == .usb)
        publish()
    }

    private func openNW(host: String, port: UInt16, video: Bool) {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcp)
        params.serviceClass = video ? .interactiveVideo : .responsiveData
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: params)
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
            if !hello.id.isEmpty, !pairedIDs.contains(hello.id) { pairedIDs.append(hello.id) }
            portrait = hello.orientation == "portrait" || hello.pixelsHigh > hello.pixelsWide
            preset = StreamPreset.preset(preset.id).oriented(portrait: portrait)
            rebuildDisplay()
        case .frameAck(let ack):
            let now = Date().timeIntervalSince1970 * 1000
            if let ms = LatencyMath.captureToAck(captureMs: ack.captureMs, ackMs: now) {
                sendControl(.xaMetrics(XAMetrics(captureToAckMs: ms, encodeMs: nil)), onVideo: true)
                tuneWiFi(rttMs: ms)
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
        case .xaBattery(let text, let heat):
            lastBatteryText = text.isEmpty ? "iPad battery: off" : text
            lastBatteryHeat = heat
            publish()
        case .xaSettings(let body):
            applySharedSettings(body, broadcast: false)
        case .xaNack(let body):
            let sequences = body.split(separator: ",").compactMap { UInt16($0) }
            udpSender.retransmit(sequences)
        case .touch, .scroll:
            if LegacyInputPolicy.acceptsUnauthenticatedVideoInput {
                log("ignored unauthenticated video input")
            }
        default:
            break
        }
    }

    private var lastHealth = HealthReport(thermal: .unknown, batteryFraction: nil, batteryState: "unknown", fpsDelivered: 0, decodeFails: 0)
    private var lastBatteryText = "iPad battery: waiting"
    private var lastBatteryHeat = false
    private var pairedIDs: [String] = []
    private var applyingRemoteSettings = false
    private let udpSender = UDPVideoSender()
    private var udpSequence: UInt16 = 1
    private var udpFrameID: UInt16 = 1
    private var linkTuner = WiFiLinkTuner()
    private var ackJitter = JitterEstimate()

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
                applyWindow(action)
            case .chrome(let op, let index, let windowIndex, let dx, let dy):
                guard settings.windowSnapping || settings.touchscreenGestures else { continue }
                applyChrome(op: op, index: index, windowIndex: windowIndex, dx: dx, dy: dy)
            case .media(let action, _):
                guard settings.mediaRemote else { continue }
                MediaKeyPoster.post(action)
            default:
                poster.post(event)
            }
        }
    }

    private func applyWindow(_ action: WindowAction) {
        let virtual = lastDisplayFrame
        let main = WindowMover.mainDisplayFrame()
        switch action {
        case .snapLeft:
            _ = WindowMover.apply(zone: .leftHalf, virtual: virtual, main: main)
        case .snapRight:
            _ = WindowMover.apply(zone: .rightHalf, virtual: virtual, main: main)
        case .fill, .snapFull, .moveToVirtual:
            _ = WindowMover.apply(zone: .full, virtual: virtual, main: main)
        case .moveToMain, .moveAcross:
            _ = WindowMover.apply(zone: .mainDisplay, virtual: virtual, main: main)
        case .saveLayout, .restoreLayout:
            break
        case .fillToggle:
            _ = WindowMover.fillToggle(on: virtual)
        case .tileTopLeft:
            _ = WindowMover.tile(.topLeft, on: virtual)
        case .tileTopRight:
            _ = WindowMover.tile(.topRight, on: virtual)
        case .tileBottomLeft:
            _ = WindowMover.tile(.bottomLeft, on: virtual)
        case .tileBottomRight:
            _ = WindowMover.tile(.bottomRight, on: virtual)
        case .pressClose, .pressMinimize, .pressZoom:
            _ = WindowMover.pressTraffic(action, on: virtual)
        case .notificationCenter:
            _ = WindowMover.pressExtra(matching: "Notification Center")
        case .controlCenter:
            _ = WindowMover.pressExtra(matching: "Control Center")
        case .missionControl:
            postShortcut(EdgeSystemAction.missionControl.shortcut)
        case .appExpose:
            postShortcut(EdgeSystemAction.appExpose.shortcut)
        case .launchpad:
            postShortcut(EdgeSystemAction.launchpad.shortcut)
        }
    }

    private func applyChrome(op: UInt8, index: UInt16, windowIndex: UInt16, dx: Double, dy: Double) {
        guard let kind = ChromeOp(rawValue: op) else { return }
        switch kind {
        case .resize:
            guard let corner = ResizeCorner(rawValue: UInt8(index)) else { return }
            let translation = XAPoint(x: dx * lastDisplayFrame.width, y: dy * lastDisplayFrame.height)
            _ = WindowMover.resize(windowIndex: Int(windowIndex), corner: corner, translation: translation, on: lastDisplayFrame)
        case .menu:
            _ = WindowMover.pressMenu(index: Int(index))
        }
    }

    private func postShortcut(_ shortcut: KeyShortcut) {
        for intent in shortcut.intents() {
            guard case .key(let phase, let code, let modifiers, let text) = intent else { continue }
            poster.post(.key(phase: phase, keyCode: code, modifiers: modifiers, text: text))
        }
    }

    private func publishChrome() {
        guard settings.touchscreenGestures, lastDisplayFrame.width > 1, dispatcher.armed else { return }
        let catalog = WindowMover.catalog(on: lastDisplayFrame)
        sendControl(.xaWindows(ChromeWire.windows(catalog.windows)), onVideo: true)
        sendControl(.xaMenus(ChromeWire.menus(catalog.menus)), onVideo: true)
        sendControl(.xaFront(catalog.bundleID), onVideo: true)
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
                self?.log("Capture \(width)x\(height) @ \(fps) \(level)")
                self?.restartAudio()
            } catch {
                self?.log("Capture failed: \(error.localizedDescription)")
                if self?.preset.id == .native {
                    self?.selectPreset(.balanced)
                }
            }
        }
    }

    private func tuneWiFi(rttMs: Double) {
        guard settings.lowLatencyWiFi, transport == .wifi else { return }
        let jitter = ackJitter.add(sampleMs: rttMs)
        let tune = linkTuner.observe(rttMs: rttMs, jitterMs: jitter)
        guard tune.changed else { return }
        if tune.preset != preset.id {
            linkTuner = WiFiLinkTuner(preferred: tune.preset)
            selectPreset(tune.preset)
        } else {
            capture.updateBitrate(tune.bitrate)
        }
    }

    private func sendVideo(_ annex: Data, keyframe: Bool, captureMs: Double, encodeMs: Double) {
        let decision = sendBudget.admit(pending: pendingSends, isKeyframe: keyframe)
        guard decision == .send else { return }
        guard annex.count <= FrameLimits.video.maxPayload else { return }
        if transport == .wifi, settings.lowLatencyWiFi {
            let packets = UDPVideoPacketizer.packetize(frame: annex, frameID: udpFrameID, nextSequence: &udpSequence, keyframe: keyframe)
            udpFrameID &+= 1
            udpSender.send(packets)
            return
        }
        pendingSends += 1
        let frame = LengthPrefixedFraming.encode(annex)
        sendRaw(frame, video: true) { [weak self] in
            self?.pendingSends = max(0, (self?.pendingSends ?? 1) - 1)
        }
        _ = captureMs
        _ = encodeMs
    }

    private func restartAudio() {
        audioCapture.stop()
        guard settings.audio, savedDisplayID != 0 else { return }
        let displayID = savedDisplayID
        let frame = lastDisplayFrame
        let mode = audioMode
        let selected = selectedAudioBundles
        audioCapture.onLog = { [weak self] line in self?.log(line) }
        audioCapture.onPacket = { [weak self] packet in
            self?.sendAudio(packet)
        }
        Task { [weak self] in
            guard let self = self else { return }
            var onDisplay: [String] = []
            if mode == .displayApps, let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) {
                onDisplay = AudioCapture.bundlesOnVirtualDisplay(content: content, displayFrame: frame)
                let apps = content.applications.map { ($0.bundleIdentifier, $0.applicationName) }
                DispatchQueue.main.async { self.knownAudioApps = apps.sorted { $0.0 < $1.0 } }
            } else if let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) {
                let apps = content.applications.map { ($0.bundleIdentifier, $0.applicationName) }
                DispatchQueue.main.async { self.knownAudioApps = apps.sorted { $0.0 < $1.0 } }
            }
            let choice = AudioRoutePlanner.choice(mode: mode, selectedBundleIDs: selected, bundlesOnDisplay: onDisplay)
            await self.audioCapture.start(displayID: displayID, choice: choice)
        }
    }

    private func sendAudio(_ packet: XAAudio) {
        guard settings.audio, dispatcher.armed else { return }
        guard AudioPolicy.accept(enabled: true, armed: true, byteCount: packet.payload.count, channels: Int(packet.channels), codec: packet.codec) else { return }
        let message = XAInputMessage.audio(
            XAAudio(
                session: dispatcher.session,
                sampleRate: packet.sampleRate,
                channels: packet.channels,
                pcm: packet.payload,
                codec: packet.codec,
                hostTimeMs: packet.hostTimeMs
            ))
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
        if settings.lowLatencyWiFi, transport == .wifi { return }
        var signals = AdaptationSignals()
        signals.thermal = lastHealth.thermal
        signals.batteryFraction = lastHealth.batteryFraction
        signals.onExternalPower = lastHealth.batteryState == "charging" || lastHealth.batteryState == "full"
        signals.decodeFailed = false
        signals.sendBacklogFrames = pendingSends
        signals.batteryHeat = lastBatteryHeat
        if let tune = adaptation.advance(dt: dt, signals: signals), tune.bitrate != 0 {
            capture.updateBitrate(tune.bitrate)
            log("Adapt \(tune.reason): \(tune.preset.rawValue) \(tune.fps)fps \(tune.bitrate)bps")
            if tune.preset != preset.id {
                selectPreset(tune.preset)
            }
        }
    }

    private func publishNowPlaying() {
        guard settings.mediaRemote, dispatcher.armed else { return }
        let name = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Mac"
        sendInput(.nowPlaying(XANowPlaying(session: dispatcher.session, appName: name)))
    }

    private func startWakeService() {
        guard settings.oneTapReconnect || settings.wifiFallback else {
            wakeListener?.cancel()
            wakeListener = nil
            return
        }
        guard wakeListener == nil else { return }
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcp)
        params.includePeerToPeer = true
        guard let port = NWEndpoint.Port(rawValue: XADisplayProtocolInfo.hostWakePort),
            let listener = try? NWListener(using: params, on: port)
        else {
            log("Wake service unavailable")
            return
        }
        let advertised = Host.current().localizedName ?? ""
        listener.service = NWListener.Service(name: advertised.isEmpty ? "XA Display" : advertised, type: XADisplayProtocolInfo.hostBonjourType)
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: self?.queue ?? .main)
            self?.log("Wake poke from the iPad")
            self?.queue.async { self?.tick() }
            self?.queue.asyncAfter(deadline: .now() + 1) { connection.cancel() }
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                self?.log("Wake service failed: \(error.localizedDescription)")
                self?.wakeListener = nil
            }
        }
        listener.start(queue: queue)
        wakeListener = listener
        log(WakeOnDemandPolicy.summary)
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
        udpSender.stop()
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

    static func loadAudioMode() -> AudioRouteMode {
        AudioRouteMode(rawValue: UserDefaults.standard.string(forKey: "XADisplayHost.audioMode") ?? "") ?? .all
    }

    static func loadAudioBundles() -> [String] {
        UserDefaults.standard.stringArray(forKey: "XADisplayHost.audioBundles") ?? []
    }

    static func saveAudio(mode: AudioRouteMode, bundles: [String]) {
        UserDefaults.standard.set(mode.rawValue, forKey: "XADisplayHost.audioMode")
        UserDefaults.standard.set(bundles, forKey: "XADisplayHost.audioBundles")
    }
}
