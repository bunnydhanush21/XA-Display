// VideoReceiver.swift
// XA Display
//
// Derived from the MIT-licensed iOS 12 receiver by cuongpham1
// (https://github.com/cuongpham1/ipad-iphone-second-monitor-ios12-free,
// commit 5ea40029a9ebf78dd83ba7651ea59cdec2ae4e54).
// The length-prefixed JSON + Annex-B video contract is implemented from that
// client's documented behavior. This file contains no OpenDisplay source.
//
// XA adds a hard frame cap, stale-frame drops, capture timestamps, and
// hardware-decoder backpressure via AVSampleBufferDisplayLayer.

import AVFoundation
import CoreMedia
import Foundation
import Network
import UIKit
import XADisplayProtocol

struct ReceiverStats {
    var fpsDelivered: Double = 0
    var handoffMs: Double = 0
    var decodeFails: Int = 0
}

protocol VideoReceiverDelegate: AnyObject {
    func videoReceiver(_ receiver: VideoReceiver, statusDidChange status: String)
    func videoReceiver(_ receiver: VideoReceiver, connected: Bool, transport: TransportKind)
    func videoReceiver(_ receiver: VideoReceiver, videoSizeDidChange size: CGSize)
    func videoReceiver(_ receiver: VideoReceiver, cursor point: CGPoint, visible: Bool)
    func videoReceiver(_ receiver: VideoReceiver, cursorImage image: UIImage, id: String)
    func videoReceiver(_ receiver: VideoReceiver, stats: ReceiverStats)
    func videoReceiverBecameXAHost(_ receiver: VideoReceiver)
    func videoReceiver(_ receiver: VideoReceiver, stream: StreamAnnouncement)
    func videoReceiver(_ receiver: VideoReceiver, metrics: XAMetrics)
    func videoReceiver(_ receiver: VideoReceiver, windows body: String)
    func videoReceiver(_ receiver: VideoReceiver, menus body: String)
    func videoReceiver(_ receiver: VideoReceiver, frontBundle bundle: String)
    func videoReceiver(_ receiver: VideoReceiver, orientation: String, mode: String, letterbox: Bool)
}

final class VideoReceiver {
    weak var delegate: VideoReceiverDelegate?
    let displayLayer: AVSampleBufferDisplayLayer
    var isConnected = false
    var transport: TransportKind = .none
    var xaHost = false
    var devicePixelsWide = 0
    var devicePixelsHigh = 0
    var deviceScale = 2.0
    var orientation = "landscape"

    var listener: NWListener?
    var connection: NWConnection?
    let queue = DispatchQueue(label: "xa.video")
    var parser = FrameParser(limits: .video)
    var lowLatency = true
    var admission = FrameAdmission()
    var udpListener: NWListener?
    var reassembler = UDPReassembler()
    let udpQueue = DispatchQueue(label: "xa.udp.video")
    var inflight = 0
    let lock = NSLock()
    var formatDesc: CMVideoFormatDescription?
    var sps: Data?
    var pps: Data?
    var port: UInt16 = XADisplayProtocolInfo.videoPort
    private let sealLock = NSLock()
    private var pairingToken = ""
    private var outboundSeal = ChannelSeal(token: "")
    var lastData = Date()
    var watchdogStarted = false
    var userPaused = false
    var deliveredThisSecond = 0
    var fpsWindow = Date()
    var stats = ReceiverStats()
    var layerFailures = 0
    var holdUntilKeyframe = false
    var pendingSize: CGSize?

    static let installID: String = {
        let key = "XADisplay.installID"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }()

    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        displayLayer.videoGravity = .resizeAspect
    }

    func start() {
        XALog.write(XALog.video, "receiver start")
        userPaused = false
        queue.async { self.startListener() }
        if !watchdogStarted {
            watchdogStarted = true
            scheduleWatchdog()
        }
    }

    func pause() {
        userPaused = true
        queue.async {
            self.connection?.cancel()
            self.connection = nil
            self.udpListener?.cancel()
            self.udpListener = nil
            self.setConnected(false, transport: .none)
        }
    }

    func ensureListening() {
        guard !userPaused else { return }
        queue.async {
            self.connection?.cancel()
            self.connection = nil
            self.listener?.cancel()
            self.listener = nil
            self.resetStream()
            self.startListener()
        }
    }

    func sendTouch(phase: String, x: Double, y: Double) {
        send(VideoControlMessage.touch(phase: phase, x: x, y: y))
    }

    func sendScroll(dx: Double, dy: Double) {
        send(VideoControlMessage.scroll(dx: dx, dy: dy))
    }

    func announcePanel() {
        send(
            VideoControlMessage.hello(
                LegacyHello(
                    pixelsWide: devicePixelsWide,
                    pixelsHigh: devicePixelsHigh,
                    scale: deviceScale,
                    device: "iPad",
                    id: Self.installID,
                    orientation: orientation
                )))
    }

    func sendOrientation(_ orientation: String, mode: String) {
        send(.xaOrient(orientation: orientation, mode: mode, letterbox: false))
    }

    func holdPictureUntilKeyframe() {
        if Thread.isMainThread {
            holdUntilKeyframe = true
        } else {
            DispatchQueue.main.async { self.holdUntilKeyframe = true }
        }
    }

    func releasePictureHold() {
        if Thread.isMainThread {
            holdUntilKeyframe = false
            pendingSize = nil
        } else {
            DispatchQueue.main.async {
                self.holdUntilKeyframe = false
                self.pendingSize = nil
            }
        }
    }

    func sendAuth(id: String, token: String) {
        let proof = ChannelAuth.proof(token: token, channel: .video, nonce: id)
        send(.xaAuth(id: id, proof: proof))
    }

    func sendSettings(_ body: String) {
        guard xaHost, !body.isEmpty else { return }
        send(.xaSettings(body))
    }

    func sendBattery(text: String, heat: Bool) {
        guard xaHost else { return }
        send(.xaBattery(text: text, heat: heat))
    }

    func sendHealth(_ health: HealthReport) {
        guard xaHost else { return }
        send(.health(health))
    }

    func sendDecodeFailed(preset: String) {
        guard xaHost else { return }
        send(.decodeFailed(preset: preset))
    }

    func send(_ message: VideoControlMessage) {
        guard let data = message.jsonData() else { return }
        queue.async { self.sendFrame(data) }
    }

    func setPairingToken(_ token: String) {
        sealLock.lock()
        pairingToken = token
        outboundSeal = ChannelSeal(token: token)
        sealLock.unlock()
    }

    func sendFrame(_ payload: Data) {
        guard let connection = connection else { return }
        sealLock.lock()
        let sealed = outboundSeal.seal(payload, aad: SealChannel.video.aad)
        sealLock.unlock()
        guard let sealed = sealed else {
            setStatus(PadError.seal.userMessage)
            return
        }
        connection.send(content: LengthPrefixedFraming.encode(sealed), completion: .contentProcessed { _ in })
    }

    func openSealed(_ frame: Data, channel: SealChannel) -> Data? {
        sealLock.lock()
        let token = pairingToken
        sealLock.unlock()
        return ChannelSeal.open(token: token, sealed: frame, aad: channel.aad)
    }

    func startListener() {
        guard !userPaused else { return }
        do {
            let tcp = NWProtocolTCP.Options()
            tcp.noDelay = true
            let params = NWParameters(tls: nil, tcp: tcp)
            params.serviceClass = .interactiveVideo
            params.allowLocalEndpointReuse = true
            guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
            listener = try NWListener(using: params, on: nwPort)
        } catch {
            setStatus(PadError.transport(error.localizedDescription).userMessage)
            return
        }
        if #available(iOS 13.0, *) {
            var txt = NWTXTRecord()
            txt["id"] = Self.installID
            listener?.service = NWListener.Service(name: UIDevice.current.name, type: XADisplayProtocolInfo.bonjourType, domain: nil, txtRecord: txt)
        } else {
            listener?.service = NWListener.Service(name: UIDevice.current.name, type: XADisplayProtocolInfo.bonjourType)
        }
        listener?.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            if case .failed = state, !self.userPaused {
                self.queue.asyncAfter(deadline: .now() + 1) {
                    self.listener?.cancel()
                    self.listener = nil
                    self.startListener()
                }
            } else if case .ready = state {
                self.setStatus("Listening on :\(self.port)")
            }
        }
        listener?.start(queue: queue)
        if lowLatency { startUDP() }
    }

    func startUDP() {
        udpListener?.cancel()
        let params = NWParameters.udp
        params.serviceClass = .interactiveVideo
        guard let port = NWEndpoint.Port(rawValue: XADisplayProtocolInfo.udpVideoPort) else { return }
        guard let listener = try? NWListener(using: params, on: port) else { return }
        listener.newConnectionHandler = { [weak self] connection in
            connection.stateUpdateHandler = { state in
                if case .ready = state { self?.receiveUDP(connection) }
            }
            connection.start(queue: self?.udpQueue ?? .main)
        }
        listener.start(queue: udpQueue)
        udpListener = listener
    }

    func receiveUDP(_ connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            if let data = data { self?.ingestDatagram(data) }
            if error == nil { self?.receiveUDP(connection) }
        }
    }

    func ingestDatagram(_ data: Data) {
        guard let packet = UDPVideoPacket.decode(data) else { return }
        if let frame = reassembler.ingest(packet) {
            queue.async {
                guard let plain = self.openSealed(frame, channel: .udp) else { return }
                self.handle(plain)
            }
        }
        let holes = reassembler.missing()
        guard !holes.isEmpty else { return }
        send(.xaNack(holes.map(String.init).joined(separator: ",")))
    }

    func accept(_ connection: NWConnection) {
        self.connection?.cancel()
        self.connection = connection
        resetStream()
        xaHost = false
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.lastData = Date()
                let kind = TransportHeuristic.classify(remoteHost: Self.remoteHost(connection))
                self.setConnected(true, transport: kind)
                self.announcePanel()
            case .failed, .cancelled:
                self.setConnected(false, transport: .none)
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive(on: connection)
    }

    func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                self.lastData = Date()
                let outcome = self.parser.append(data, now: Date().timeIntervalSince1970)
                switch outcome {
                case .ok(let frames):
                    for frame in frames {
                        guard let plain = self.openSealed(frame, channel: .video) else {
                            connection.cancel()
                            self.setStatus(PadError.seal.userMessage)
                            return
                        }
                        self.handle(plain)
                    }
                case .failed:
                    connection.cancel()
                    self.setStatus(PadError.malformed.userMessage)
                    return
                }
            }
            if error != nil || isComplete {
                self.setConnected(false, transport: .none)
                return
            }
            self.receive(on: connection)
        }
    }

    private static func remoteHost(_ connection: NWConnection) -> String {
        switch connection.endpoint {
        case .hostPort(let host, _):
            return "\(host)"
        default:
            return ""
        }
    }
}
