import Foundation
import XADisplayProtocol

extension HostController {
    func installOutboundSeal(_ seal: ChannelSeal) {
        outboundSeal = seal
        videoOut.replace(seal)
    }

    func publishVideoLink() {
        videoOut.note(fd: usbFD?.fd)
    }

    func deliverVideo(_ product: VideoSendQueue.Product, countSend: Bool) {
        switch product {
        case .idle:
            break
        case .tcp(let frame):
            guard wifiVideo != nil || usbFD != nil else { break }
            sendRaw(frame, video: true) { [weak self] in
                Task { @MainActor in self?.pendingSends = max(0, (self?.pendingSends ?? 1) - 1) }
            }
            return
        case .udp(let packets):
            udpSender.send(packets)
        }
        guard countSend else { return }
        pendingSends = max(0, pendingSends - 1)
    }

    func flushVideoOutbound() { videoOut.flush() }
}
