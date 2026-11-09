import Darwin
import Foundation

/// Seals video off the caller and, for a USB file descriptor, writes one contiguous buffer.
public final class VideoSendQueue: @unchecked Sendable {
    private let queue = DispatchQueue(label: "xa.video.out")
    private var seal: ChannelSeal
    private var fileDescriptor: Int32 = -1
    private var udpSequence: UInt16 = 1
    private var udpFrameID: UInt16 = 1

    /// A sealed frame ready for the socket, or `idle` when the bytes were already written.
    public enum Product: Sendable {
        case idle
        case tcp(Data)
        case udp([UDPVideoPacket])
    }

    public init(seal: ChannelSeal) {
        self.seal = seal
    }

    public func replace(_ seal: ChannelSeal) {
        queue.sync { self.seal = seal }
    }

    public func sealSync(_ payload: Data, aad: Data) -> Data? {
        queue.sync { self.seal.seal(payload, aad: aad) }
    }

    public func note(fd: Int32?) {
        let descriptor = fd ?? -1
        queue.async { self.fileDescriptor = descriptor }
    }

    public func submit(payload: Data, aad: Data, udp: Bool, keyframe: Bool, done: @escaping @Sendable (Product) -> Void) {
        queue.async {
            if udp {
                guard let sealed = self.seal.seal(payload, aad: aad) else {
                    done(.idle)
                    return
                }
                let packets = UDPVideoPacketizer.packetize(frame: sealed, frameID: self.udpFrameID, nextSequence: &self.udpSequence, keyframe: keyframe)
                self.udpFrameID &+= 1
                done(.udp(packets))
                return
            }
            guard let frame = self.seal.sealPrefixed(payload, aad: aad) else {
                done(.idle)
                return
            }
            if self.fileDescriptor >= 0 {
                Self.writeAll(self.fileDescriptor, frame)
                done(.idle)
                return
            }
            done(.tcp(frame))
        }
    }

    public func flush() { queue.sync {} }

    private static func writeAll(_ fd: Int32, _ data: Data) {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < raw.count {
                let n = Darwin.write(fd, base.advanced(by: sent), raw.count - sent)
                if n <= 0 { return }
                sent += n
            }
        }
    }
}
