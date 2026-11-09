@preconcurrency import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import Darwin
@preconcurrency import Foundation
@preconcurrency import Network
@preconcurrency import ScreenCaptureKit
import XADisplayProtocol

extension HostController {
    func applyWindow(_ action: WindowAction) {
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
    func applyChrome(op: UInt8, index: UInt16, windowIndex: UInt16, dx: Double, dy: Double) {
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
    func postShortcut(_ shortcut: KeyShortcut) {
        for intent in shortcut.intents() {
            guard case .key(let phase, let code, let modifiers, let text) = intent else { continue }
            poster.post(.key(phase: phase, keyCode: code, modifiers: modifiers, text: text))
        }
    }
    func publishChrome() {
        guard settings.touchscreenGestures, lastDisplayFrame.width > 1, dispatcher.armed else { return }
        let catalog = WindowMover.catalog(on: lastDisplayFrame)
        sendControl(.xaWindows(ChromeWire.windows(catalog.windows)), onVideo: true)
        sendControl(.xaMenus(ChromeWire.menus(catalog.menus)), onVideo: true)
        sendControl(.xaFront(catalog.bundleID), onVideo: true)
    }
    func applyOrientation(requested: String, mode: String) {
        let portraitSize = PortraitModes.size(preset: preset.id)
        let landscape = PortraitModes.landscape(preset: preset.id)
        let decision = OrientationPolicy.action(
            currentPortrait: portrait,
            requested: requested,
            follow: settings.followRotation,
            lock: settings.orientationLock,
            mode: mode,
            portraitSize: portraitSize,
            landscapeSize: landscape
        )
        switch decision {
        case .ignore:
            ensureDisplay()
        case .letterbox:
            ensureDisplay()
            sendControl(.xaOrient(orientation: requested, mode: "resolution", letterbox: true), onVideo: true)
        case .rotateStream:
            if portrait {
                let previous = preset
                let previousPortrait = portrait
                portrait = false
                preset = StreamPreset.preset(preset.id).oriented(portrait: false)
                rebuildDisplay { [weak self] ok in
                    guard let self = self else { return }
                    if ok {
                        self.sendControl(.xaOrient(orientation: "portrait", mode: "stream", letterbox: false), onVideo: true)
                    } else {
                        self.preset = previous
                        self.portrait = previousPortrait
                        self.sendControl(.xaOrient(orientation: requested, mode: "resolution", letterbox: true), onVideo: true)
                    }
                }
            } else {
                ensureDisplay()
                sendControl(.xaOrient(orientation: "portrait", mode: "stream", letterbox: false), onVideo: true)
            }
        case .reconfigure(let width, let height):
            let previous = preset
            let previousPortrait = portrait
            portrait = height > width
            var next = StreamPreset.preset(preset.id)
            next.width = width
            next.height = height
            preset = next
            rebuildDisplay { [weak self] ok in
                guard let self = self else { return }
                if ok {
                    let applied = self.portrait ? "portrait" : "landscape"
                    self.sendControl(.xaOrient(orientation: applied, mode: "resolution", letterbox: false), onVideo: true)
                } else {
                    self.preset = previous
                    self.portrait = previousPortrait
                    self.sendControl(.xaOrient(orientation: requested, mode: "resolution", letterbox: true), onVideo: true)
                }
            }
        }
    }
    func ensureDisplay() {
        if display.displayID == 0 { rebuildDisplay() }
    }
    func applyHello(_ hello: LegacyHello) {
        if !hello.id.isEmpty, !pairedIDs.contains(hello.id) { pairedIDs.append(hello.id) }
        lastDeviceOrientation = (hello.orientation == "portrait" || hello.pixelsHigh > hello.pixelsWide) ? "portrait" : "landscape"
        applyOrientation(requested: lastDeviceOrientation, mode: settings.rotationMode)
    }
    func rebuildDisplay(completion: ((Bool) -> Void)? = nil) {
        if settings.custom.enabled {
            let spec = settings.custom.clamped()
            adaptation.applyOverride(fps: spec.fps, bitrate: spec.bitrate)
        }
        let active =
            settings.custom.enabled
            ? settings.custom.clamped().applying(to: StreamPreset.preset(preset.id)).oriented(portrait: portrait)
            : preset
        let pixelsWide = active.width
        let pixelsHigh = active.height
        let scale = preset.id == .native ? 2.0 : 1.0
        let ok = display.applyPixelWidth(UInt32(pixelsWide), height: UInt32(pixelsHigh), scale: scale, name: "XA Display")
        guard ok, display.displayID != 0 else {
            log(HostError.virtualDisplay)
            publish()
            completion?(false)
            return
        }
        savedDisplayID = display.displayID
        lastDisplayFrame = WindowMover.displayFrame(display.displayID)
        dispatcher.displayFrame = lastDisplayFrame
        dispatcher.videoPixelSize = XASize(width: Double(pixelsWide), height: Double(pixelsHigh))
        restartCaptureIfNeeded()
        let announcement = StreamAnnouncement(
            preset: preset.id.rawValue,
            width: pixelsWide,
            height: pixelsHigh,
            fps: adaptation.fps,
            bitrate: adaptation.bitrate,
            experimental: preset.experimental
        )
        sendControl(.xaStream(announcement), onVideo: true)
        publish()
        completion?(true)
    }
    func restartCaptureIfNeeded() {
        guard savedDisplayID != 0, CGPreflightScreenCaptureAccess() else { return }
        capture.stop()
        let width = preset.width
        let height = preset.height
        let fps = adaptation.fps
        let bitrate = adaptation.bitrate
        let level = preset.profileLevelName
        let audio = settings.audio
        let displayID = savedDisplayID
        Task { @MainActor [weak self] in
            do {
                try await self?.capture.start(displayID: displayID, width: width, height: height, fps: fps, bitrate: bitrate, profileLevel: level, audio: audio)
                self?.capture.onAccessUnit = { data, key, _, captureMs, encodeMs in
                    let payload = data
                    let isKey = key
                    let captured = captureMs
                    let encoded = encodeMs
                    Task { @MainActor [weak self] in
                        self?.sendVideo(payload, keyframe: isKey, captureMs: captured, encodeMs: encoded)
                    }
                }
                self?.log("Capture \(width)x\(height) @ \(fps) \(level)")
                self?.restartAudio()
            } catch {
                self?.log(HostFailure.codec.error)
                if self?.preset.id == .native {
                    self?.selectPreset(.balanced)
                }
            }
        }
    }
    func tuneWiFi(rttMs: Double) {
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
    func sendVideo(_ annex: Data, keyframe: Bool, captureMs: Double, encodeMs: Double) {
        guard inputService.allowsVideo(channelGate) else { return }
        let decision = sendBudget.admit(pending: pendingSends, isKeyframe: keyframe)
        guard decision == .send else { return }
        guard annex.count + ChannelSeal.overhead <= FrameLimits.video.maxPayload else { return }
        let udp = transport == .wifi && settings.lowLatencyWiFi
        guard let sealed = outboundSeal.seal(annex, aad: (udp ? SealChannel.udp : SealChannel.video).aad) else {
            log(HostError.seal)
            return
        }
        if udp {
            let packets = UDPVideoPacketizer.packetize(frame: sealed, frameID: udpFrameID, nextSequence: &udpSequence, keyframe: keyframe)
            udpFrameID &+= 1
            udpSender.send(packets)
            return
        }
        pendingSends += 1
        let frame = LengthPrefixedFraming.encode(sealed)
        sendRaw(frame, video: true) { [weak self] in
            Task { @MainActor in self?.pendingSends = max(0, (self?.pendingSends ?? 1) - 1) }
        }
        _ = captureMs
        _ = encodeMs
    }
    func restartAudio() {
        audioCapture.stop()
        guard audioService.shouldCapture(enabled: settings.audio, displayID: savedDisplayID) else { return }
        let displayID = savedDisplayID
        let frame = lastDisplayFrame
        let mode = audioMode
        let selected = selectedAudioBundles
        audioCapture.onLog = { [weak self] line in
            let text = line
            let host = self
            Task { @MainActor [host] in
                host?.log(text)
            }
        }
        audioCapture.onPacket = { [weak self] packet in
            let copy = packet
            let host = self
            Task { @MainActor [host] in
                host?.sendAudio(copy)
            }
        }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            var onDisplay: [String] = []
            if mode == .displayApps, let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) {
                onDisplay = AudioCapture.bundlesOnVirtualDisplay(content: content, displayFrame: frame)
                let apps = content.applications.map { ($0.bundleIdentifier, $0.applicationName) }
                self.knownAudioApps = apps.sorted { $0.0 < $1.0 }
            } else if let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) {
                let apps = content.applications.map { ($0.bundleIdentifier, $0.applicationName) }
                self.knownAudioApps = apps.sorted { $0.0 < $1.0 }
            }
            let choice = AudioRoutePlanner.choice(mode: mode, selectedBundleIDs: selected, bundlesOnDisplay: onDisplay)
            await self.audioCapture.start(displayID: displayID, choice: choice)
        }
    }
    func sendAudio(_ packet: XAAudio) {
        channelGate.noteInputArmed(dispatcher.armed)
        guard settings.audio, channelGate.allows(.audio) else { return }
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
    func sendControl(_ message: VideoControlMessage, onVideo: Bool) {
        guard let payload = message.jsonData() else { return }
        let channel: SealChannel = onVideo ? .video : .input
        guard let frame = sealedFrame(payload, channel: channel) else { return }
        sendRaw(frame, video: onVideo, done: nil)
    }
    func sendInput(_ message: XAInputMessage) {
        guard let payload = try? message.encode(), let frame = sealedFrame(payload, channel: .input) else { return }
        sendRaw(frame, video: false, done: nil)
    }
    func sealedFrame(_ payload: Data, channel: SealChannel) -> Data? {
        guard sessionReady || settings.legacyTokenSeal else { return nil }
        guard let sealed = outboundSeal.seal(payload, aad: channel.aad) else {
            log(HostError.seal)
            return nil
        }
        return LengthPrefixedFraming.encode(sealed)
    }
    func openFrame(_ frame: Data, channel: SealChannel) -> Data? {
        guard sessionReady || settings.legacyTokenSeal else { return nil }
        return inboundSeal.open(sealed: frame, aad: channel.aad)
    }
}
