@preconcurrency import Darwin
@preconcurrency import Foundation
@preconcurrency import Network
import XADisplayProtocol

/// Seals and writes video off the main actor. One contiguous buffer, one write.
final class VideoOutbound: @unchecked Sendable {
    private let queue = DispatchQueue(label: "xa.video.out")
    private var seal: ChannelSeal
    private var fileDescriptor: Int32 = -1
    private var connection: NWConnection?
    private var sender: UDPVideoSender?
    private var udpSequence: UInt16 = 1
    private var udpFrameID: UInt16 = 1

    init(seal: ChannelSeal) {
        self.seal = seal
    }

    func replace(_ seal: ChannelSeal) {
        queue.sync { self.seal = seal }
    }

    func sealSync(_ payload: Data, aad: Data) -> Data? {
        queue.sync { self.seal.seal(payload, aad: aad) }
    }

    func note(fd: Int32?, connection: NWConnection?, sender: UDPVideoSender) {
        let descriptor = fd ?? -1
        queue.async {
            self.fileDescriptor = descriptor
            self.connection = connection
            self.sender = sender
        }
    }

    func submit(payload: Data, aad: Data, udp: Bool, keyframe: Bool, done: @escaping @Sendable () -> Void) {
        queue.async {
            if udp {
                guard let sealed = self.seal.seal(payload, aad: aad) else {
                    done()
                    return
                }
                let packets = UDPVideoPacketizer.packetize(frame: sealed, frameID: self.udpFrameID, nextSequence: &self.udpSequence, keyframe: keyframe)
                self.udpFrameID &+= 1
                self.sender?.send(packets)
                done()
                return
            }
            guard let frame = self.seal.sealPrefixed(payload, aad: aad) else {
                done()
                return
            }
            if self.fileDescriptor >= 0 {
                Self.writeAll(self.fileDescriptor, frame)
                done()
                return
            }
            if let connection = self.connection {
                connection.send(content: frame, completion: .contentProcessed { _ in done() })
                return
            }
            done()
        }
    }

    func flush() { queue.sync {} }

    private static func writeAll(_ fd: Int32, _ data: Data) {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < raw.count {
                let n = write(fd, base.advanced(by: sent), raw.count - sent)
                if n <= 0 { return }
                sent += n
            }
        }
    }
}
