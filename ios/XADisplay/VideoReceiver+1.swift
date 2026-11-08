import AVFoundation
import CoreMedia
import Foundation
import Network
import UIKit
import XADisplayProtocol

extension VideoReceiver {
    func handle(_ payload: Data) {
        dispatchPrecondition(condition: .onQueue(queue))
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
        let maxAge = lowLatency ? 80.0 : 150.0
        let cap = lowLatency ? 1 : 3
        let decision = admission.decide(isKeyframe: idr, queued: inflight, ageMs: age.isFinite ? age : 0, maxAgeMs: maxAge)
        let allow = decision == .show && inflight < cap
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
    func handleControl(_ message: VideoControlMessage) {
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
        case .xaOrient(let orientation, let mode, let letterbox):
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.videoReceiver(self, orientation: orientation, mode: mode, letterbox: letterbox)
            }
        default:
            break
        }
    }
    func buildFormat(sps: Data, pps: Data) {
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
                        if self.holdUntilKeyframe {
                            self.pendingSize = size
                        } else {
                            self.displayLayer.flush()
                            self.delegate?.videoReceiver(self, videoSizeDidChange: size)
                        }
                    }
                }
                return result
            }
        }
        if status != noErr { noteFailure() }
    }
    func enqueue(_ nalus: [Data], keyframe: Bool) -> Bool {
        guard let formatDesc = formatDesc else { return false }
        let holding = holdUntilKeyframe
        if keyframe, !holding { displayLayer.flush() }
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
        if keyframe, holding {
            holdUntilKeyframe = false
            if let pendingSize = pendingSize {
                self.pendingSize = nil
                delegate?.videoReceiver(self, videoSizeDidChange: pendingSize)
            }
        }
        return true
    }
    func noteDelivered(handoffMs: Double) {
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
    func noteFailure() {
        stats.decodeFails += 1
        layerFailures += 1
        delegate?.videoReceiver(self, stats: stats)
        if layerFailures == 3 {
            sendDecodeFailed(preset: "current")
        }
    }
    func resetStream() {
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
    func scheduleWatchdog() {
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
    func setStatus(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.videoReceiver(self, statusDidChange: text)
        }
    }
}
