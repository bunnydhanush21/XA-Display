@preconcurrency import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import Darwin
@preconcurrency import Foundation
@preconcurrency import Network
@preconcurrency import ScreenCaptureKit
import XADisplayProtocol

extension HostController {
    func sendRaw(_ data: Data, video: Bool, done: (() -> Void)?) {
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
    func pollClipboard() {
        channelGate.noteInputArmed(dispatcher.armed)
        guard settings.clipboardSync, channelGate.allows(.clipboard) else { return }
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
    func adapt(dt: Double) {
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
    func publishNowPlaying() {
        guard settings.mediaRemote, dispatcher.armed else { return }
        let name = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Mac"
        sendInput(.nowPlaying(XANowPlaying(session: dispatcher.session, appName: name)))
    }
    func startWakeService() {
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
    func startBrowser() {
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
    func resolve(name: String) {
        let connection = NWConnection(to: .service(name: name, type: XADisplayProtocolInfo.bonjourType, domain: "local", interface: nil), using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state, let path = connection.currentPath, case .hostPort(let host, _) = path.remoteEndpoint {
                self?.wifiHost = "\(host)"
                connection.cancel()
            }
        }
        connection.start(queue: queue)
    }
    func linkClosed() {
        let events = dispatcher.disconnect()
        apply(events)
        closeLinks()
        transport = .none
        transition(.linkLost)
        publish()
    }
    func releaseInput(reason: String) {
        log(reason)
        apply(dispatcher.disconnect())
    }
    func closeLinks() {
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
        channelGate.reset()
        channelGate.requireAuth = settings.requirePairing
        pendingHello = nil
    }
    func persist() {
        HostStore.save(token: token, settings: settings, presets: library.items)
        publish()
    }
    func menuSnapshot() -> MenuSnapshot {
        MenuSnapshot(
            phase: displayedPhase,
            peerName: pairedIDs.last ?? "iPad",
            transport: transport.rawValue,
            latency: lastLatency,
            fps: lastFPS,
            preset: preset.id.rawValue,
            audio: settings.audio,
            clipboard: settings.clipboardSync,
            touch: settings.touchscreenGestures,
            lowLatency: settings.lowLatencyWiFi,
            screenRecording: CGPreflightScreenCaptureAccess(),
            accessibility: AXIsProcessTrusted()
        )
    }
    func publish() {
        let text = "\(transport.rawValue) · \(preset.id.rawValue) \(preset.width)×\(preset.height)"
        DispatchQueue.main.async { self.onState?(text) }
    }
    func transition(_ event: ConnectionEvent) {
        Task { [weak self] in
            guard let self = self else { return }
            let phase = await self.session.send(event)
            DispatchQueue.main.async {
                self.displayedPhase = phase
                self.onPhase?(phase)
            }
        }
    }
    func log(_ line: String) {
        let clean = LogRing.redact(line)
        logs.append(clean)
        logRing.append(clean)
        if logs.count > 40 { logs.removeFirst(logs.count - 40) }
        XALog.write(XALog.net, clean)
    }
}
