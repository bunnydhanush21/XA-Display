import CoreMedia
import Foundation
import VideoToolbox
import XADisplayProtocol

final class FrameMark: NSObject {
    let captureMs: Double
    let started: CFTimeInterval
    let sequence: UInt64
    init(captureMs: Double, started: CFTimeInterval, sequence: UInt64) {
        self.captureMs = captureMs
        self.started = started
        self.sequence = sequence
    }
}

final class H264Encoder {
    var onAccessUnit: ((Data, Bool, UInt64, Double, Double) -> Void)?
    private var session: VTCompressionSession?
    private var gate = InFlightGate()
    private var sequence: UInt64 = 0
    private var width = 0
    private var height = 0
    private var fps = 30
    private var bitrate = 8_000_000
    private var profileLevel = "H264_Main_4_1"
    private let lock = NSLock()

    func start(width: Int, height: Int, fps: Int, bitrate: Int, profileLevel: String) -> Bool {
        stop()
        self.width = width
        self.height = height
        self.fps = fps
        self.bitrate = bitrate
        self.profileLevel = profileLevel
        gate = InFlightGate()
        return createSession(lowLatency: true) || createSession(lowLatency: false)
    }

    func stop() {
        if let session = session {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
        }
        session = nil
    }

    func updateBitrate(_ bitrate: Int) {
        self.bitrate = bitrate
        guard let session = session else { return }
        let value = bitrate as CFNumber
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: value)
        let bytes = max(bitrate, 1) / 8
        let limits: [Int] = [bytes * 3 / 2, 1]
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: limits as CFArray)
    }

    func encode(_ pixelBuffer: CVPixelBuffer, captureMs: Double) {
        guard let session = session else { return }
        let permit: InFlightGate.Permit = lock.xaWithLock { gate.begin() }
        guard case .encode(let force) = permit else { return }
        sequence &+= 1
        let mark = FrameMark(captureMs: captureMs, started: CACurrentMediaTime(), sequence: sequence)
        var flags: VTEncodeInfoFlags = []
        var properties: CFDictionary?
        if force {
            properties = [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary
        }
        let markPointer = Unmanaged.passRetained(mark).toOpaque()
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: CMTime(value: CMTimeValue(sequence), timescale: CMTimeScale(max(fps, 1))),
            duration: .invalid,
            frameProperties: properties,
            sourceFrameRefcon: markPointer,
            infoFlagsOut: &flags
        )
        if status != noErr {
            Unmanaged<FrameMark>.fromOpaque(markPointer).release()
            lock.xaWithLock {
                gate.finished()
                gate.needsKeyframe = true
            }
        }
    }

    private func createSession(lowLatency: Bool) -> Bool {
        var spec: [CFString: Any] = [
            kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true,
        ]
        if lowLatency {
            spec[kVTVideoEncoderSpecification_EnableLowLatencyRateControl] = true
        }
        var created: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: spec as CFDictionary,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: encoderOutput,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &created
        )
        guard status == noErr, let created = created else { return false }
        session = created
        let realTime = kCFBooleanTrue
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_RealTime, value: realTime)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_ProfileLevel, value: profileLevel as CFString)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fps as CFNumber)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: max(fps, 1) as CFNumber)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: 1 as CFNumber)
        updateBitrate(bitrate)
        VTCompressionSessionPrepareToEncodeFrames(created)
        return true
    }

    fileprivate func handle(_ sample: CMSampleBuffer, mark: FrameMark) {
        lock.xaWithLock { gate.finished() }
        let encodeMs = (CACurrentMediaTime() - mark.started) * 1000
        guard let unit = annexB(from: sample, sequence: mark.sequence, captureMs: mark.captureMs, encodeMs: encodeMs) else { return }
        let keyframe = !isNotSync(sample)
        onAccessUnit?(unit, keyframe, mark.sequence, mark.captureMs, encodeMs)
    }
}

private func encoderOutput(refcon: UnsafeMutableRawPointer?, sourceFrameRefCon: UnsafeMutableRawPointer?, status: OSStatus, infoFlags: VTEncodeInfoFlags, sampleBuffer: CMSampleBuffer?) {
    guard status == noErr, let sampleBuffer = sampleBuffer, let refcon = refcon else { return }
    let encoder = Unmanaged<H264Encoder>.fromOpaque(refcon).takeUnretainedValue()
    let mark: FrameMark
    if let sourceFrameRefCon = sourceFrameRefCon {
        mark = Unmanaged<FrameMark>.fromOpaque(sourceFrameRefCon).takeRetainedValue()
    } else {
        mark = FrameMark(captureMs: Date().timeIntervalSince1970 * 1000, started: CACurrentMediaTime(), sequence: 0)
    }
    encoder.handle(sampleBuffer, mark: mark)
}

private func isNotSync(_ sample: CMSampleBuffer) -> Bool {
    guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]],
          let value = attachments.first?[kCMSampleAttachmentKey_NotSync] else { return false }
    return (value as? Bool) == true
}

private func annexB(from sample: CMSampleBuffer, sequence: UInt64, captureMs: Double, encodeMs: Double) -> Data? {
    guard let dataBuffer = CMSampleBufferGetDataBuffer(sample) else { return nil }
    var total = 0
    var pointer: UnsafeMutablePointer<Int8>?
    guard CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &total, dataPointerOut: &pointer) == noErr,
          let pointer = pointer, total > 0 else { return nil }
    let bytes = UnsafeRawBufferPointer(start: pointer, count: total)
    var nalus: [Data] = []
    var offset = 0
    while offset + 4 <= total {
        let length = Int(UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16 | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3]))
        offset += 4
        guard length > 0, offset + length <= total else { break }
        nalus.append(Data(bytes[offset..<(offset + length)]))
        offset += length
    }
    var prefix: Data?
    prefix = try? JSONSerialization.data(withJSONObject: ["type": "timing", "seq": Int(sequence), "captureMs": captureMs, "encodeMs": encodeMs], options: [])
    var parameterSets: [Data] = []
    if let format = CMSampleBufferGetFormatDescription(sample), !isNotSync(sample) {
        var count = 0
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil)
        for index in 0..<count {
            var ptr: UnsafePointer<UInt8>?
            var size = 0
            if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: index, parameterSetPointerOut: &ptr, parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil) == noErr, let ptr = ptr {
                parameterSets.append(Data(bytes: ptr, count: size))
            }
        }
    }
    return AnnexB.encode(timingJSON: prefix, nalus: nalus, prependParameterSets: parameterSets)
}

private extension NSLock {
    func xaWithLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
