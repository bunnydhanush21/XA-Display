import Foundation
import XADisplayProtocol

extension HostController {
    func installOutboundSeal(_ seal: ChannelSeal) {
        outboundSeal = seal
        videoOut.replace(seal)
    }

    func publishVideoLink() {
        videoOut.note(fd: usbFD?.fd, connection: wifiVideo, sender: udpSender)
    }

    func flushVideoOutbound() { videoOut.flush() }
}
