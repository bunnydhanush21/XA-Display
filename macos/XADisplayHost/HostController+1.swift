@preconcurrency import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import Darwin
@preconcurrency import Foundation
@preconcurrency import Network
@preconcurrency import ScreenCaptureKit
import XADisplayProtocol

extension HostController {
    func applySharedSettings(_ body: String, broadcast: Bool) {
        let current = settingsDocument()
        let merged = SettingsSync.apply(body, to: current)
        if merged.features.requirePairing != current.features.requirePairing { setRequirePairing(merged.features.requirePairing) }
        if merged.features.clipboardSync != current.features.clipboardSync { setClipboard(merged.features.clipboardSync) }
        if merged.features.audio != current.features.audio { setAudio(merged.features.audio) }
        if merged.features.wifiFallback != current.features.wifiFallback { setWiFi(merged.features.wifiFallback) }
        if merged.features.autoConnectUSB != current.features.autoConnectUSB { setAutoConnect(merged.features.autoConnectUSB) }
        if merged.features.lowLatencyWiFi != current.features.lowLatencyWiFi { setLowLatencyWiFi(merged.features.lowLatencyWiFi) }
        let orientationChanged =
            merged.features.followRotation != current.features.followRotation
            || merged.features.orientationLock != current.features.orientationLock
            || merged.features.rotationMode != current.features.rotationMode
        if orientationChanged {
            settings.followRotation = merged.features.followRotation
            settings.orientationLock = merged.features.orientationLock
            settings.rotationMode = merged.features.rotationMode
            persist()
            applyOrientation(requested: lastDeviceOrientation, mode: settings.rotationMode)
        }
        if merged.features.windowSnapping != current.features.windowSnapping { setWindowSnapping(merged.features.windowSnapping) }
        if merged.features.mediaRemote != current.features.mediaRemote { setMediaRemote(merged.features.mediaRemote) }
        if merged.audioMode != current.audioMode, let mode = AudioRouteMode(rawValue: merged.audioMode) { setAudioMode(mode) }
        if merged.preset != current.preset, let id = StreamPreset.ID(rawValue: merged.preset) { selectPreset(id) }
        if merged.features.custom != current.features.custom || merged.features.launchAtLogin != current.features.launchAtLogin {
            settings.custom = merged.features.custom.clamped()
            settings.launchAtLogin = merged.features.launchAtLogin
            LoginItem.setEnabled(settings.launchAtLogin)
            persist()
            rebuildDisplay()
        }
        if broadcast { sendControl(.xaSettings(SettingsSync.encode(settingsDocument())), onVideo: true) }
    }
    func applyLocalDocument(_ document: XASettingsDocument, broadcast: Bool) {
        applySharedSettings(SettingsSync.encode(document), broadcast: broadcast)
        settings.touchscreenGestures = document.features.touchscreenGestures
        settings.trackpadMode = document.features.trackpadMode
        settings.threeFingerShortcuts = document.features.threeFingerShortcuts
        settings.gestureTuning = document.features.gestureTuning
        dispatcher.windowActionsEnabled = settings.windowSnapping || settings.touchscreenGestures
        persist()
    }
    func tick() {
        let usb = !UsbmuxClient.listUSBDevices().isEmpty
        if let desired = connectionService.link(
            running: running, userPaused: userPaused, autoUSB: settings.autoConnectUSB, transport: transport, usb: usb, wifiHost: wifiHost, wifiAllowed: settings.wifiFallback)
        {
            connect(desired)
        }
        adapt(dt: 1.5)
    }
    func connect(_ kind: TransportKind) {
        apply(dispatcher.disconnect())
        closeLinks()
        transport = kind
        guard kind != .none else {
            publish()
            return
        }
        log("Connecting over \(kind.rawValue)")
        transition(.beginConnect)
        if kind == .usb {
            guard let device = UsbmuxClient.listUSBDevices().first,
                let video = UsbmuxClient.connect(deviceID: device.deviceID, port: XADisplayProtocolInfo.videoPort)
            else {
                transport = .none
                publish()
                return
            }
            let stream = FDStream(fd: video)
            stream.onData = { [weak self] data in Task { @MainActor in self?.ingestVideo(data) } }
            stream.onClose = { [weak self] in Task { @MainActor in self?.linkClosed() } }
            usbFD = stream
            if let input = UsbmuxClient.connect(deviceID: device.deviceID, port: XADisplayProtocolInfo.inputPort) {
                let inputStream = FDStream(fd: input)
                inputStream.onData = { [weak self] data in Task { @MainActor in self?.ingestInput(data) } }
                inputStream.onClose = { [weak self] in Task { @MainActor in self?.releaseInput(.transport("The input link closed.")) } }
                inputFD = inputStream
            }
            sendControl(.xaHello, onVideo: true)
            transition(.transportReady)
            if !settings.requirePairing { transition(.authAccepted) }
        } else if let host = wifiHost {
            openNW(host: host, port: XADisplayProtocolInfo.videoPort, video: true)
            openNW(host: host, port: XADisplayProtocolInfo.inputPort, video: false)
            if settings.lowLatencyWiFi { udpSender.connect(host: host) }
            sendControl(.xaHello, onVideo: true)
            transition(.transportReady)
            if !settings.requirePairing { transition(.authAccepted) }
        }
        adaptation = AdaptationController(preset: preset.id, usb: kind == .usb)
        publish()
    }
    func openNW(host: String, port: UInt16, video: Bool) {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcp)
        params.serviceClass = video ? .interactiveVideo : .responsiveData
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: params)
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                if case .ready = state, video {
                    self?.sendControl(.xaHello, onVideo: true)
                }
                if case .failed = state { self?.linkClosed() }
            }
        }
        connection.start(queue: queue)
        receiveNW(connection, video: video)
        if video { wifiVideo = connection } else { wifiInput = connection }
    }
    func receiveNW(_ connection: NWConnection, video: Bool) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                if let data = data {
                    if video { self?.ingestVideo(data) } else { self?.ingestInput(data) }
                }
                if error != nil || isComplete { return }
                self?.receiveNW(connection, video: video)
            }
        }
    }
    func ingestVideo(_ data: Data) {
        switch videoParser.append(data, now: Date().timeIntervalSince1970) {
        case .ok(let frames):
            for frame in frames {
                guard let plain = openFrame(frame, channel: .video) else {
                    log(HostError.seal)
                    linkClosed()
                    return
                }
                handleVideo(plain)
            }
        case .failed:
            log(HostFailure.transport.error)
            linkClosed()
        }
    }
    func ingestInput(_ data: Data) {
        switch inputParser.append(data, now: Date().timeIntervalSince1970) {
        case .ok(let frames):
            for frame in frames {
                guard let plain = openFrame(frame, channel: .input) else {
                    releaseInput(.seal)
                    return
                }
                do {
                    if let message = try XAInputMessage.decode(plain) {
                        handleInput(message)
                    }
                } catch {
                    log(HostError.transport("The input message could not be decoded."))
                    linkClosed()
                    return
                }
            }
        case .failed:
            log(HostFailure.transport.error)
            releaseInput(.transport("The input frame was malformed."))
        }
    }
    func handleVideo(_ payload: Data) {
        guard PayloadKind.classify(payload) == .controlJSON else { return }
        let message = VideoControlMessage.parse(payload)
        switch message {
        case .xaAuth(let id, let proof):
            let accepted = channelGate.acceptVideo(token: token, nonce: id, proof: proof)
            if accepted {
                log("Video channel accepted")
            } else {
                log(HostError.pairing)
            }
            transition(accepted ? .authAccepted : .authRejected)
            if accepted, let hello = pendingHello {
                pendingHello = nil
                applyHello(hello)
            }
            publish()
            return
        case .hello(let hello):
            pendingHello = hello
            transition(.helloAccepted)
            if channelGate.allows(.video) { applyHello(hello) }
            return
        default:
            break
        }
        guard inputService.allowsVideo(channelGate) else {
            log(HostFailure.pairing.error)
            return
        }
        switch message {
        case .xaOrient(let orientation, let mode, _):
            lastDeviceOrientation = orientation
            applyOrientation(requested: orientation, mode: mode)
        case .frameAck(let ack):
            let now = Date().timeIntervalSince1970 * 1000
            lastLatency = "—"
            if let ms = LatencyMath.captureToAck(captureMs: ack.captureMs, ackMs: now) {
                lastLatency = String(format: "%.0f ms", ms)
                sendControl(.xaMetrics(XAMetrics(captureToAckMs: ms, encodeMs: nil)), onVideo: true)
                tuneWiFi(rttMs: ms)
            }
        case .health(let health):
            lastHealth = health
            lastFPS = String(format: "%.0f fps", health.fpsDelivered)
        case .decodeFailed:
            if let next = PresetFallback.afterDecodeFailure(preset.id) {
                log(HostFailure.codec.error)
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
                log(HostError.pairing)
            }
        default:
            break
        }
    }
    func handleInput(_ message: XAInputMessage) {
        let outcome = dispatcher.handle(message, hostNowMs: Date().timeIntervalSince1970 * 1000)
        apply(outcome)
    }
    func apply(_ outcome: DispatchOutcome) {
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
    func apply(_ events: [PostedEvent]) {
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
}
