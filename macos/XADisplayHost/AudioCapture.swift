@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
@preconcurrency import Foundation
@preconcurrency import ScreenCaptureKit
import XADisplayProtocol

/// Separate from the video stream so app audio filters do not crop the picture.
final class AudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    var onPacket: ((XAAudio) -> Void)?
    var onLog: ((String) -> Void)?
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "xa.audio")
    private let encoder = AACLCEncoder()
    private var running = false

    func start(displayID: CGDirectDisplayID, choice: AudioFilterChoice) async {
        XALog.write(XALog.audio, "audio start")
        stop()
        if case .includingBundles(let ids) = choice, ids.isEmpty {
            onLog?("Audio route has no apps")
            return
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                onLog?("Audio display missing")
                return
            }
            let filter = try Self.filter(display: display, content: content, choice: choice)
            let config = SCStreamConfiguration()
            config.width = 64
            config.height = 64
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 48_000
            config.channelCount = 2
            config.queueDepth = 3
            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            try await stream.startCapture()
            self.stream = stream
            running = true
            _ = encoder.start()
            onLog?("Audio route \(Self.describe(choice))")
        } catch {
            onLog?("Audio capture failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        running = false
        stream?.stopCapture()
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard running, type == .audio, let pcm = Self.pcm16(from: sampleBuffer), pcm.count >= 4 else { return }
        let hostMs = Date().timeIntervalSince1970 * 1000
        if let encoded = encoder.encode(pcm), let packed = AACPacket.pack(cookie: encoder.cookie, frame: encoded),
            AudioPolicy.accept(enabled: true, armed: true, byteCount: packed.count, channels: 2, codec: .aac)
        {
            onPacket?(XAAudio(session: 0, sampleRate: 48_000, channels: 2, pcm: packed, codec: .aac, hostTimeMs: hostMs))
            return
        }
        let clipped = pcm.count > XAAudio.maxBytes ? pcm.prefix(XAAudio.maxBytes) : pcm
        guard AudioPolicy.accept(enabled: true, armed: true, byteCount: clipped.count, channels: 2, codec: .pcm) else { return }
        onPacket?(XAAudio(session: 0, sampleRate: 48_000, channels: 2, pcm: Data(clipped), codec: .pcm, hostTimeMs: hostMs))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onLog?("Audio stopped: \(error.localizedDescription)")
    }

    static func filter(display: SCDisplay, content: SCShareableContent, choice: AudioFilterChoice) throws -> SCContentFilter {
        switch choice {
        case .allApplications:
            return SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        case .includingBundles(let ids):
            let apps = content.applications.filter { ids.contains($0.bundleIdentifier) }
            guard !apps.isEmpty else { throw CaptureError.displayNotFound }
            return SCContentFilter(display: display, including: apps, exceptingWindows: [])
        }
    }

    static func describe(_ choice: AudioFilterChoice) -> String {
        switch choice {
        case .allApplications: return "all system audio"
        case .includingBundles(let ids): return ids.joined(separator: ", ")
        }
    }

    static func bundlesOnVirtualDisplay(content: SCShareableContent, displayFrame: XARect) -> [String] {
        let windows = WindowMover.windows().map { (pid: $0.snapshot.ownerPID, bounds: $0.snapshot.bounds) }
        var bundles: [Int: String] = [:]
        for app in content.applications {
            bundles[Int(app.processID)] = app.bundleIdentifier
        }
        return AudioRoutePlanner.bundleIDsOnDisplay(windows: windows, display: displayFrame, bundlesByPID: bundles)
    }

    private static func pcm16(from sample: CMSampleBuffer) -> Data? {
        guard let format = CMSampleBufferGetFormatDescription(sample),
            let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(format)
        else { return nil }
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
            sample, bufferListSizeNeededOut: nil,
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
        return pcm.isEmpty ? nil : pcm
    }
}

final class AACLCEncoder: @unchecked Sendable {
    private var converter: AVAudioConverter?
    private(set) var cookie = Data()

    func start() -> Bool {
        guard let input = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48_000, channels: 2, interleaved: true),
            let output = AVAudioFormat(settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 64_000
            ]),
            let converter = AVAudioConverter(from: input, to: output)
        else { return false }
        self.converter = converter
        let description = output.formatDescription
        var size = 0
        if let pointer = CMAudioFormatDescriptionGetMagicCookie(description, sizeOut: &size), size > 0 {
            cookie = Data(bytes: pointer, count: size)
        }
        return true
    }

    func encode(_ pcm: Data) -> Data? {
        guard let converter = converter,
            let inputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48_000, channels: 2, interleaved: true),
            let outputFormat = AVAudioFormat(settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2
            ])
        else { return nil }
        let bytesPerFrame = Int(inputFormat.streamDescription.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0 else { return nil }
        let frames = AVAudioFrameCount(pcm.count / bytesPerFrame)
        guard frames >= 1024, let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frames) else { return nil }
        inputBuffer.frameLength = frames
        let copied = pcm.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            let destination = inputBuffer.audioBufferList.pointee.mBuffers.mData
            guard let destination = destination else { return false }
            memcpy(destination, base, min(pcm.count, Int(inputBuffer.audioBufferList.pointee.mBuffers.mDataByteSize)))
            return true
        }
        guard copied else { return nil }
        let compressed = AVAudioCompressedBuffer(format: outputFormat, packetCapacity: 8, maximumPacketSize: 512)
        var consumed = false
        var error: NSError?
        converter.convert(to: compressed, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return inputBuffer
        }
        guard error == nil, compressed.byteLength > 0 else { return nil }
        return Data(bytes: compressed.data, count: Int(compressed.byteLength))
    }
}
