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
}

final class VideoReceiver {
    weak var delegate: VideoReceiverDelegate?
    let displayLayer: AVSampleBufferDisplayLayer
    private(set) var isConnected = false
    private(set) var transport: TransportKind = .none
    private(set) var xaHost = false
    var devicePixelsWide = 0
    var devicePixelsHigh = 0
    var deviceScale = 2.0
    var orientation = "landscape"

    private var listener: NWListener?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "xa.video")
    private var parser = FrameParser(limits: .video)
    private var admission = FrameAdmission()
    private var inflight = 0
    private let lock = NSLock()
    private var formatDesc: CMVideoFormatDescription?
    private var sps: Data?
    private var pps: Data?
    private var port: UInt16 = XADisplayProtocolInfo.videoPort
    private var lastData = Date()
    private var watchdogStarted = false
    private var userPaused = false
    private var deliveredThisSecond = 0
    private var fpsWindow = Date()
    private var stats = ReceiverStats()
    private var layerFailures = 0

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

    private func send(_ message: VideoControlMessage) {
        guard let data = message.jsonData() else { return }
        queue.async { self.sendFrame(data) }
    }

    private func sendFrame(_ payload: Data) {
        guard let connection = connection else { return }
        connection.send(content: LengthPrefixedFraming.encode(payload), completion: .contentProcessed { _ in })
    }

    private func startListener() {
        guard !userPaused else { return }
        do {
            let tcp = NWProtocolTCP.Options()
            tcp.noDelay = true
            let params = NWParameters(tls: nil, tcp: tcp)
            params.allowLocalEndpointReuse = true
            guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
            listener = try NWListener(using: params, on: nwPort)
        } catch {
            setStatus("Listener failed: \(error.localizedDescription)")
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
    }

    private func accept(_ connection: NWConnection) {
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

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                self.lastData = Date()
                let outcome = self.parser.append(data, now: Date().timeIntervalSince1970)
                switch outcome {
                case .ok(let frames):
                    for frame in frames { self.handle(frame) }
                case .failed:
                    connection.cancel()
                    self.setStatus("Closed a malformed video frame")
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

    private func handle(_ payload: Data) {
        if PayloadKind.classify(payload) == .controlJSON {
            handleControl(VideoControlMessage.parse(payload))
            return
        }
        let received = CACurrentMediaTime()
        let unit = AnnexB.parse(payload)
        if unit.truncated || unit.nalus.isEmpty {
            lock.lock()
            admission.awaitingKeyframe = true
            lock.unlock()
            return
        }
        var idr = false
        var vcl: [Data] = []
        for nalu in unit.nalus {
            switch nalu.type {
            case 7:
                if sps != nalu.data {
                    sps = nalu.data
                    formatDesc = nil
                }
            case 8:
                if pps != nalu.data {
                    pps = nalu.data
                    formatDesc = nil
                }
            case 6:
                break
            case 5:
                idr = true
                vcl.append(nalu.data)
            default:
                vcl.append(nalu.data)
            }
        }
        if formatDesc == nil, let sps = sps, let pps = pps {
            buildFormat(sps: sps, pps: pps)
        }
        guard !vcl.isEmpty, formatDesc != nil else { return }
        let age = unit.timing.map { max(0, received * 1000 - $0.captureMs) } ?? 0
        lock.lock()
        let decision = admission.decide(isKeyframe: idr, queued: inflight, ageMs: age.isFinite ? age : 0)
        let allow = decision == .show && inflight < 3
        if allow { inflight += 1 }
        lock.unlock()
        guard allow else { return }
        let timing = unit.timing
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let enqueued = self.enqueue(vcl, keyframe: idr)
            let now = CACurrentMediaTime()
            self.lock.lock()
            self.inflight = max(0, self.inflight - 1)
            self.lock.unlock()
            if enqueued {
                self.noteDelivered(handoffMs: (now - received) * 1000)
                if let timing = timing, self.xaHost {
                    let ack = FrameAck(seq: timing.seq, captureMs: timing.captureMs, receiveMs: received * 1000, enqueueMs: now * 1000)
                    self.send(.frameAck(ack))
                }
            } else {
                self.noteFailure()
            }
        }
    }

    private func handleControl(_ message: VideoControlMessage) {
        switch message {
        case .ping(let t):
            send(.pong(t: t, mt: Date().timeIntervalSince1970 * 1000))
        case .xaHello:
            xaHost = true
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.videoReceiverBecameXAHost(self)
            }
        case .cursor(let x, let y, let visible):
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.videoReceiver(self, cursor: CGPoint(x: x, y: y), visible: visible)
            }
        case .cursorImage(let image):
            guard let ui = UIImage(data: image.png) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.videoReceiver(self, cursorImage: ui, id: image.id)
            }
        case .xaStream(let stream):
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.videoReceiver(self, stream: stream)
            }
        case .xaMetrics(let metrics):
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.videoReceiver(self, metrics: metrics)
            }
        case .xaWindows(let body):
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.videoReceiver(self, windows: body)
            }
        case .xaMenus(let body):
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.videoReceiver(self, menus: body)
            }
        case .xaFront(let bundle):
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.videoReceiver(self, frontBundle: bundle)
            }
        default:
            break
        }
    }

    private func buildFormat(sps: Data, pps: Data) {
        let status: OSStatus = sps.withUnsafeBytes { spsRaw in
            pps.withUnsafeBytes { ppsRaw in
                let pointers = [
                    spsRaw.bindMemory(to: UInt8.self).baseAddress!,
                    ppsRaw.bindMemory(to: UInt8.self).baseAddress!
                ]
                let sizes = [sps.count, pps.count]
                var desc: CMVideoFormatDescription?
                let result = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: pointers,
                    parameterSetSizes: sizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &desc
                )
                if result == noErr, let desc = desc {
                    formatDesc = desc
                    let dims = CMVideoFormatDescriptionGetDimensions(desc)
                    let size = CGSize(width: Int(dims.width), height: Int(dims.height))
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.displayLayer.flush()
                        self.delegate?.videoReceiver(self, videoSizeDidChange: size)
                    }
                }
                return result
            }
        }
        if status != noErr { noteFailure() }
    }

    private func enqueue(_ nalus: [Data], keyframe: Bool) -> Bool {
        guard let formatDesc = formatDesc else { return false }
        if keyframe { displayLayer.flush() }
        if displayLayer.status == .failed {
            displayLayer.flush()
            noteFailure()
            return false
        }
        guard displayLayer.isReadyForMoreMediaData else {
            lock.lock()
            admission.awaitingKeyframe = true
            lock.unlock()
            return false
        }
        var avcc = Data()
        for nalu in nalus {
            var len = UInt32(nalu.count).bigEndian
            avcc.append(Data(bytes: &len, count: 4))
            avcc.append(nalu)
        }
        var block: CMBlockBuffer?
        guard
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: avcc.count,
                blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
                dataLength: avcc.count, flags: 0, blockBufferOut: &block
            ) == noErr, let block = block
        else { return false }
        let copied = avcc.withUnsafeBytes { raw -> OSStatus in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: avcc.count)
        }
        guard copied == noErr else { return false }
        var sample: CMSampleBuffer?
        var sizes = [avcc.count]
        guard
            CMSampleBufferCreateReady(
                allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: formatDesc,
                sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil,
                sampleSizeEntryCount: 1, sampleSizeArray: &sizes, sampleBufferOut: &sample
            ) == noErr, let sample = sample
        else { return false }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true), CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        displayLayer.enqueue(sample)
        return true
    }

    private func noteDelivered(handoffMs: Double) {
        if let measured = LatencyMath.handoff(receiveMs: 0, enqueueMs: handoffMs) {
            stats.handoffMs = measured
        } else if handoffMs >= 0, handoffMs < 5_000 {
            stats.handoffMs = handoffMs
        }
        deliveredThisSecond += 1
        let now = Date()
        if now.timeIntervalSince(fpsWindow) >= 1 {
            stats.fpsDelivered = Double(deliveredThisSecond) / now.timeIntervalSince(fpsWindow)
            deliveredThisSecond = 0
            fpsWindow = now
            layerFailures = 0
        }
        let snapshot = stats
        delegate?.videoReceiver(self, stats: snapshot)
    }

    private func noteFailure() {
        stats.decodeFails += 1
        layerFailures += 1
        delegate?.videoReceiver(self, stats: stats)
        if layerFailures == 3 {
            sendDecodeFailed(preset: "current")
        }
    }

    private func resetStream() {
        parser = FrameParser(limits: .video)
        admission = FrameAdmission()
        inflight = 0
        formatDesc = nil
        sps = nil
        pps = nil
        DispatchQueue.main.async { [weak self] in
            self?.displayLayer.flush()
        }
    }

    private func scheduleWatchdog() {
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self else { return }
            if let started = self.parser.partialStartedAt {
                let outcome = self.parser.tick(now: Date().timeIntervalSince1970)
                if case .failed = outcome, let connection = self.connection {
                    connection.cancel()
                }
                _ = started
            }
            if let connection = self.connection, connection.state == .ready, Date().timeIntervalSince(self.lastData) > 6 {
                connection.cancel()
                self.connection = nil
                self.setConnected(false, transport: .none)
            }
            self.scheduleWatchdog()
        }
    }

    private func setStatus(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.videoReceiver(self, statusDidChange: text)
        }
    }

    private func setConnected(_ connected: Bool, transport: TransportKind) {
        isConnected = connected
        self.transport = connected ? transport : .none
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.videoReceiver(self, connected: connected, transport: self.transport)
        }
        if !connected { setStatus(userPaused ? "Disconnected" : "Listening on :\(port)") }
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
