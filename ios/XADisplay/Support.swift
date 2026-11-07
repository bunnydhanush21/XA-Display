import AudioToolbox
import Foundation
import UIKit
import XADisplayProtocol

enum LocalSettings {
    static let tokenKey = "XADisplay.pairingToken"
    static let featuresKey = "XADisplay.features"

    static func load() -> (token: String, features: XAFeatureSettings) {
        let token = UserDefaults.standard.string(forKey: tokenKey) ?? ""
        if let data = UserDefaults.standard.data(forKey: featuresKey),
           let features = try? JSONDecoder().decode(XAFeatureSettings.self, from: data) {
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
        DiagnosticsText.render(DiagnosticsSnapshot(
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
