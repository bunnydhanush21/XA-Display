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
        lock.lock()
        metricsWindow.noteReceived(bytes: payload.count)
        lock.unlock()
        guard let picture = preparePicture(payload, received: received) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.display(picture)
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
        guard let block = framePool.block(nalus: nalus), let sample = makeSample(block: block, format: formatDesc, bytes: nalus.reduce(0) { $0 + 4 + $1.count }) else { return false }
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
            lock.lock()
            let sample = metricsWindow.snapshot(now: now, inputRoundTripMilliseconds: nil)
            lock.unlock()
            latestMetrics = sample
            stats.receivedFramesPerSecond = sample.receivedFramesPerSecond
            stats.droppedFrames = sample.droppedFrames
            stats.inboundBitsPerSecond = sample.inboundBitsPerSecond
            stats.decodeTimeMilliseconds = sample.decodeTimeMilliseconds
            stats.endToEndLatencyMilliseconds = sample.endToEndLatencyMilliseconds
            deliveredThisSecond = 0
            fpsWindow = now
            layerFailures = 0
        }
        guard statsPace.allow(now: now, force: false) else { return }
        let snapshot = stats
        delegate?.videoReceiver(self, stats: snapshot)
    }
    func noteFailure() {
        XALog.event(XALog.video, "failure", ["code": PadError.decode.userMessage])
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
