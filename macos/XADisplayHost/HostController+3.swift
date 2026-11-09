@preconcurrency import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import Darwin
@preconcurrency import Foundation
@preconcurrency import Network
@preconcurrency import ScreenCaptureKit
import XADisplayProtocol

extension HostController {
    func sendRaw(_ data: Data, video: Bool, done: (@Sendable () -> Void)?) {
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
        guard let text = board.string(forType: .string) else { return }
        guard let outbound = clipboardService.outbound(sync: settings.clipboardSync, armed: dispatcher.armed, changeCount: board.changeCount, lastCount: pasteboardCount, text: text) else { return }
        pasteboardCount = board.changeCount
        clipboardRevision &+= 1
        sendInput(.clipboard(XAClipboard(session: dispatcher.session, seq: UInt32(truncatingIfNeeded: clipboardRevision), revision: clipboardRevision, text: outbound)))
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
            log(HostError.wakeUnavailable)
            return
        }
        let advertised = Host.current().localizedName ?? ""
        listener.service = NWListener.Service(name: advertised.isEmpty ? "XA Display" : advertised, type: XADisplayProtocolInfo.hostBonjourType)
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .main)
            connection.cancel()
            Task { @MainActor in
                self?.log("Wake poke from the iPad")
                self?.tick()
            }
        }
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                if case .failed(let error) = state {
                    self?.log(HostError.transport(error.localizedDescription))
                    self?.wakeListener = nil
                }
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
                Task { @MainActor in self?.resolve(name: name) }
            }
        }
        browser.start(queue: queue)
        self.browser = browser
    }
    func resolve(name: String) {
        let connection = NWConnection(to: .service(name: name, type: XADisplayProtocolInfo.bonjourType, domain: "local", interface: nil), using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state, let path = connection.currentPath, case .hostPort(let host, _) = path.remoteEndpoint {
                let name = "\(host)"
                connection.cancel()
                Task { @MainActor in self?.wifiHost = name }
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
    func releaseInput(_ failure: HostError) {
        log(failure)
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
        publishVideoLink()
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
        onState?(text)
    }
    func transition(_ event: ConnectionEvent) {
        Task { @MainActor in
            let phase = await self.session.send(event)
            self.displayedPhase = phase
            self.onPhase?(phase)
        }
    }
    func log(_ line: String) {
        let clean = LogRing.redact(line)
        logs.append(clean)
        logRing.append(clean)
        if logs.count > 40 { logs.removeFirst(logs.count - 40) }
        XALog.event(XALog.net, "note", ["message": clean])
    }
    func log(_ failure: HostError) {
        log(failure.userMessage)
        XALog.event(XALog.net, "failure", ["code": String(describing: failure)])
    }
}
