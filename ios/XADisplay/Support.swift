import AVFoundation
import AudioToolbox
import Foundation
import UIKit
import XADisplayProtocol

enum LocalSettings {
    static let tokenKey = "XADisplay.pairingToken"
    static let featuresKey = "XADisplay.features"
    static let assistKey = "XADisplay.touchAssist"

    static func load() -> (token: String, features: XAFeatureSettings) {
        let token = UserDefaults.standard.string(forKey: tokenKey) ?? ""
        if let data = UserDefaults.standard.data(forKey: featuresKey),
            let features = try? JSONDecoder().decode(XAFeatureSettings.self, from: data)
        {
            return (token, features)
        }
        return (token, XAFeatureSettings())
    }

    static func save(token: String, features: XAFeatureSettings) {
        UserDefaults.standard.set(token, forKey: tokenKey)
        if let data = try? JSONEncoder().encode(features) {
            UserDefaults.standard.set(data, forKey: featuresKey)
        }
    }

    static func loadAssist() -> TouchAssist {
        guard let data = UserDefaults.standard.data(forKey: assistKey),
            let assist = try? JSONDecoder().decode(TouchAssist.self, from: data)
        else { return TouchAssist() }
        return assist
    }

    static func saveAssist(_ assist: TouchAssist) {
        if let data = try? JSONEncoder().encode(assist) {
            UserDefaults.standard.set(data, forKey: assistKey)
        }
    }
}

final class PCMPlayer {
    private var queue: AudioQueueRef?
    private var running = false

    func start() {
        guard queue == nil else { return }
        var format = AudioStreamBasicDescription(
            mSampleRate: 48_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        let status = AudioQueueNewOutput(&format, { _, _, _ in }, nil, nil, nil, 0, &queue)
        guard status == noErr else {
            queue = nil
            return
        }
        AudioQueueStart(queue!, nil)
        running = true
    }

    func stop() {
        if let queue = queue {
            AudioQueueStop(queue, true)
            AudioQueueDispose(queue, true)
        }
        queue = nil
        running = false
    }

    func setVolume(_ volume: Float) {
        guard let queue = queue else { return }
        AudioQueueSetParameter(queue, kAudioQueueParam_Volume, volume)
    }

    func enqueue(_ pcm: Data) {
        guard running, let queue = queue, pcm.count >= 4, pcm.count <= XAAudio.maxBytes else { return }
        var buffer: AudioQueueBufferRef?
        guard AudioQueueAllocateBuffer(queue, UInt32(pcm.count), &buffer) == noErr, let buffer = buffer else { return }
        pcm.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            memcpy(buffer.pointee.mAudioData, base, pcm.count)
        }
        buffer.pointee.mAudioDataByteSize = UInt32(pcm.count)
        if AudioQueueEnqueueBuffer(queue, buffer, 0, nil) != noErr {
            AudioQueueFreeBuffer(queue, buffer)
        }
    }
}

final class RoutedAudioPlayer {
    var volume: Double {
        didSet { output.setVolume(Float(min(1, max(0, volume)))) }
    }
    private var jitter = AudioJitterQueue()
    private let output = PCMPlayer()
    private var timer: Timer?
    private let decoder = AACLCDecoder()

    init() {
        volume = UserDefaults.standard.object(forKey: "XADisplay.audioVolume") as? Double ?? 1
    }

    func start() {
        output.start()
        output.setVolume(Float(volume))
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.015, repeats: true) { [weak self] _ in
            self?.pump()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        jitter = AudioJitterQueue()
        output.stop()
    }

    func setClockOffset(_ offset: Double) {
        jitter.offsetClientMinusHost = offset
    }

    func push(_ packet: XAAudio) {
        guard AudioPolicy.accept(enabled: true, armed: true, byteCount: packet.payload.count, channels: Int(packet.channels), codec: packet.codec) else { return }
        let pcm: Data?
        switch packet.codec {
        case .pcm:
            pcm = packet.payload
        case .aac:
            guard let parts = AACPacket.unpack(packet.payload) else { return }
            pcm = decoder.decode(cookie: parts.cookie, frame: parts.frame)
        }
        guard let pcm = pcm else { return }
        let shaped = AudioVolume.scalePCM16(pcm: pcm, volume: volume)
        _ = jitter.push(hostMs: packet.hostTimeMs, payload: shaped)
    }

    private func pump() {
        let now = Date().timeIntervalSince1970 * 1000
        while let slot = jitter.popReady(nowClientMs: now) {
            output.enqueue(slot.payload)
        }
    }
}

final class AACLCDecoder {
    func decode(cookie: Data, frame: Data) -> Data? {
        guard
            let aac = AVAudioFormat(settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2
            ]), let pcmFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48_000, channels: 2, interleaved: true),
            let converter = AVAudioConverter(from: aac, to: pcmFormat)
        else { return nil }
        _ = cookie
        let compressed = AVAudioCompressedBuffer(format: aac, packetCapacity: 1, maximumPacketSize: frame.count)
        frame.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                memcpy(compressed.data, base, frame.count)
            }
        }
        compressed.byteLength = UInt32(frame.count)
        compressed.packetCount = 1
        if let descriptions = compressed.packetDescriptions {
            descriptions[0].mStartOffset = 0
            descriptions[0].mDataByteSize = UInt32(frame.count)
            descriptions[0].mVariableFramesInPacket = 0
        }
        guard let pcm = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: 4096) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: pcm, error: &error) { _, status in
            if consumed {
                status.pointee = .endOfStream
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return compressed
        }
        guard error == nil, pcm.frameLength > 0 else { return nil }
        let list = pcm.audioBufferList.pointee.mBuffers
        guard let data = list.mData else { return nil }
        return Data(bytes: data, count: Int(list.mDataByteSize))
    }
}

final class ClipboardBridge {
    var enabled = false
    var onLocalCopy: ((String) -> Void)?
    private var lastRevision: UInt64 = 0
    private var suppress = false
    private var timer: Timer?

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func applyRemote(text: String, revision: UInt64) {
        guard enabled, revision > lastRevision else { return }
        lastRevision = revision
        suppress = true
        UIPasteboard.general.string = text
        suppress = false
    }

    private func poll() {
        guard enabled, !suppress, let text = UIPasteboard.general.string else { return }
        let count = UInt64(UIPasteboard.general.changeCount)
        guard count != lastRevision, text.utf8.count <= XAClipboard.maxBytes else { return }
        lastRevision = count
        onLocalCopy?(text)
    }
}

enum DiagnosticsCopy {
    static func text(features: XAFeatureSettings, token: String, transport: String, preset: String, thermal: String, battery: String, notes: [String]) -> String {
        DiagnosticsText.render(
            DiagnosticsSnapshot(
                appVersion: "1.0.0",
                transport: transport,
                preset: preset,
                permissions: ["localNetwork": true],
                pairingToken: token,
                thermal: thermal,
                battery: battery,
                notes: notes
            ))
    }
}
