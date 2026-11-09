import Foundation
import XADisplayProtocol

extension HostController {
    func sendHelloIfReady() {
        guard sessionReady || settings.legacyTokenSeal else { return }
        sendControl(.xaHello, onVideo: true)
    }

    @discardableResult
    func acceptHandshake(_ frame: Data) -> Data? {
        if pendingHandshake == nil {
            guard let answer = SessionHandshake.hostAnswer(token: token, offer: frame, replay: &handshakeReplay) else {
                log(HostError.pairing)
                return
            }
            pendingHandshake = answer.state
            sendRaw(LengthPrefixedFraming.encode(answer.reply), video: true, done: nil)
            return answer.reply
        }
        guard let pending = pendingHandshake, let keys = SessionHandshake.hostConfirm(token: token, state: pending, finish: frame) else {
            log(HostError.pairing)
            pendingHandshake = nil
            return nil
        }
        installOutboundSeal(ChannelSeal(rawKey: keys.hostToPad, connectionID: pending.connectionID))
        inboundSeal = SealInbox(rawKey: keys.padToHost)
        sessionReady = true
        pendingHandshake = nil
        sendHelloIfReady()
        return nil
    }
}
