import CoreMedia
import Foundation
import QuartzCore
import XADisplayProtocol

struct PreparedPicture {
    var sample: CMSampleBuffer
    var keyframe: Bool
    var timing: TimingPrefix?
    var received: CFTimeInterval
}

extension VideoReceiver {
    func openSealed(_ frame: Data, channel: SealChannel) -> Data? {
        guard openIntoScratch(frame, channel: channel) else { return nil }
        return Data(inboundScratch)
    }

    func openIntoScratch(_ frame: Data, channel: SealChannel) -> Bool {
        sealLock.lock()
        defer { sealLock.unlock() }
        guard sessionReady || legacyTokenSeal else { return false }
        return inboundSeal.open(sealed: frame, aad: channel.aad, into: &inboundScratch)
    }

    func preparePicture(_ payload: Data, received: CFTimeInterval) -> PreparedPicture? {
        let view = AnnexBSpan.scan(payload)
        if view.truncated || view.spans.isEmpty {
            lock.lock()
            admission.awaitingKeyframe = true
            lock.unlock()
            return nil
        }
        var idr = false
        var vcl: [NALSpan] = []
        let formatChanged = payload.withUnsafeBytes { raw -> Bool in
            var changed = false
            for span in view.spans {
                switch span.type {
                case 7:
                    if !matches(sps, span, raw) {
                        sps = copy(span, raw)
                        changed = true
                    }
                case 8:
                    if !matches(pps, span, raw) {
                        pps = copy(span, raw)
                        changed = true
                    }
                case 6:
                    break
                case 5:
                    idr = true
                    vcl.append(span)
                default:
                    vcl.append(span)
                }
            }
            return changed
        }
        if formatChanged { formatDesc = nil }
        if formatDesc == nil, let sps = sps, let pps = pps { buildFormat(sps: sps, pps: pps) }
        guard !vcl.isEmpty, formatDesc != nil else { return nil }
        let age = view.timing.map { max(0, received * 1000 - $0.captureMs) } ?? 0
        lock.lock()
        let maxAge = lowLatency ? 80.0 : 150.0
        let cap = lowLatency ? 1 : 3
        let decision = admission.decide(isKeyframe: idr, queued: inflight, ageMs: age.isFinite ? age : 0, maxAgeMs: maxAge)
        let allow = decision == .show && inflight < cap
        if allow { inflight += 1 }
        lock.unlock()
        guard allow else {
            lock.lock()
            metricsWindow.noteDropped()
            lock.unlock()
            return nil
        }
        let sample = payload.withUnsafeBytes { raw -> CMSampleBuffer? in
            guard let block = framePool.block(source: raw, spans: vcl), let format = formatDesc else { return nil }
            return makeSample(block: block, format: format, bytes: AnnexBSpan.avccByteCount(vcl))
        }
        guard let sample else {
            lock.lock()
            inflight = max(0, inflight - 1)
            lock.unlock()
            return nil
        }
        return PreparedPicture(sample: sample, keyframe: idr, timing: view.timing, received: received)
    }

    func display(_ picture: PreparedPicture) {
        dispatchPrecondition(condition: .onQueue(.main))
        let holding = holdUntilKeyframe
        if picture.keyframe, !holding { displayLayer.flush() }
        if displayLayer.status == .failed {
            displayLayer.flush()
            finishPicture(false, picture: picture)
            return
        }
        guard displayLayer.isReadyForMoreMediaData else {
            lock.lock()
            admission.awaitingKeyframe = true
            lock.unlock()
            finishPicture(false, picture: picture)
            return
        }
        displayLayer.enqueue(picture.sample)
        if picture.keyframe, holding {
            holdUntilKeyframe = false
            if let pendingSize {
                self.pendingSize = nil
                delegate?.videoReceiver(self, videoSizeDidChange: pendingSize)
            }
        }
        finishPicture(true, picture: picture)
    }

    func finishPicture(_ enqueued: Bool, picture: PreparedPicture) {
        let now = CACurrentMediaTime()
        lock.lock()
        inflight = max(0, inflight - 1)
        lock.unlock()
        if enqueued {
            let decodeMs = max(0, (now - picture.received) * 1000)
            lock.lock()
            metricsWindow.noteDisplayed(
                decodeMilliseconds: decodeMs,
                captureHostMs: picture.timing?.captureMs,
                displayedClientMs: now * 1000,
                clientMinusHostMs: clockOffsetClientMinusHost
            )
            lock.unlock()
            noteDelivered(handoffMs: (now - picture.received) * 1000)
            if let timing = picture.timing, xaHost {
                let ack = FrameAck(seq: timing.seq, captureMs: timing.captureMs, receiveMs: picture.received * 1000, enqueueMs: now * 1000)
                send(.frameAck(ack))
            }
        } else {
            noteFailure()
        }
    }

    func makeSample(block: CMBlockBuffer, format: CMVideoFormatDescription, bytes: Int) -> CMSampleBuffer? {
        var sample: CMSampleBuffer?
        var sizes = [bytes]
        guard
            CMSampleBufferCreateReady(
                allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
                sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil,
                sampleSizeEntryCount: 1, sampleSizeArray: &sizes, sampleBufferOut: &sample
            ) == noErr, let sample
        else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true), CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dict,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }
        return sample
    }

    func matches(_ stored: Data?, _ span: NALSpan, _ raw: UnsafeRawBufferPointer) -> Bool {
        guard let stored, stored.count == span.count, let base = raw.baseAddress else { return false }
        return stored.withUnsafeBytes { left in
            guard let leftBase = left.baseAddress else { return false }
            return memcmp(leftBase, base.advanced(by: span.start), span.count) == 0
        }
    }

    func copy(_ span: NALSpan, _ raw: UnsafeRawBufferPointer) -> Data {
        guard let base = raw.baseAddress else { return Data() }
        return Data(bytes: base.advanced(by: span.start), count: span.count)
    }
}
