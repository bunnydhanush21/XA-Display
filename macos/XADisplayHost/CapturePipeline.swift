import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

enum CaptureError: Error {
    case displayNotFound
    case encoderFailed
}

final class CapturePipeline: NSObject, SCStreamOutput, SCStreamDelegate {
    var onAccessUnit: ((Data, Bool, UInt64, Double, Double) -> Void)?
    var onPCM: ((Data) -> Void)?
    var onLog: ((String) -> Void)?
    private var stream: SCStream?
    private let encoder = H264Encoder()
    private let queue = DispatchQueue(label: "xa.capture")
    private var audioEnabled = false

    func start(displayID: CGDirectDisplayID, width: Int, height: Int, fps: Int, bitrate: Int, profileLevel: String, audio: Bool) async throws {
        audioEnabled = audio
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        config.showsCursor = false
        config.queueDepth = 3
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(fps, 1)))
        config.scalesToFit = true
        config.capturesAudio = audio
        if audio {
            config.sampleRate = 48_000
            config.channelCount = 2
        }
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if audio {
            try? stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        }
        guard encoder.start(width: width, height: height, fps: fps, bitrate: bitrate, profileLevel: profileLevel) else {
            throw CaptureError.encoderFailed
        }
        encoder.onAccessUnit = { [weak self] data, key, seq, capture, encode in
            self?.onAccessUnit?(data, key, seq, capture, encode)
        }
        try await stream.startCapture()
        self.stream = stream
    }

    func updateBitrate(_ bitrate: Int) {
        encoder.updateBitrate(bitrate)
    }

    func stop() {
        stream?.stopCapture()
        stream = nil
        encoder.stop()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if type == .audio {
            if audioEnabled, let pcm = Self.pcm16(from: sampleBuffer) {
                onPCM?(pcm)
            }
            return
        }
        guard sampleBuffer.isValid, let pixel = sampleBuffer.imageBuffer else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let raw = attachments.first?[.status] as? Int,
           SCFrameStatus(rawValue: raw) == .idle {
            return
        }
        encoder.encode(pixel, captureMs: Date().timeIntervalSince1970 * 1000)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onLog?("Capture stopped: \(error.localizedDescription)")
    }

    private static func pcm16(from sample: CMSampleBuffer) -> Data? {
        guard let format = CMSampleBufferGetFormatDescription(sample),
              let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(format) else { return nil }
        let asbd = asbdPointer.pointee
        var sizeNeeded = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sample, bufferListSizeNeededOut: &sizeNeeded, bufferListOut: nil, bufferListSize: 0,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil
        )
        guard sizeNeeded > 0 else { return nil }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: sizeNeeded, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        var block: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sample,
            bufferListSizeNeededOut: nil,
            bufferListOut: raw.assumingMemoryBound(to: AudioBufferList.self),
            bufferListSize: sizeNeeded,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &block
        )
        guard status == noErr else { return nil }
        let buffers = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        var pcm = Data()
        let isFloat = (asbd.mFormatFlags & kLinearPCMFormatFlagIsFloat) != 0
        for buffer in buffers {
            guard let data = buffer.mData, buffer.mDataByteSize > 0 else { continue }
            if isFloat {
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                let samples = data.bindMemory(to: Float.self, capacity: count)
                for index in 0..<count {
                    let clamped = max(-1 as Float, min(1, samples[index]))
                    var converted = Int16(clamped * 32_767)
                    withUnsafeBytes(of: &converted) { pcm.append(contentsOf: $0) }
                }
            } else {
                pcm.append(Data(bytes: data, count: Int(buffer.mDataByteSize)))
            }
        }
        if pcm.count > XAAudio.maxBytes {
            pcm = pcm.prefix(XAAudio.maxBytes)
        }
        return pcm.isEmpty ? nil : pcm
    }
}
