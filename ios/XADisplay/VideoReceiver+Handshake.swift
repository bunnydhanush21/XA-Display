import Foundation
import Network
import XADisplayProtocol

extension VideoReceiver {
    func beginHandshakeIfNeeded() {
        guard !legacyTokenSeal, clientHandshake == nil, let offer = SessionHandshake.clientOffer() else { return }
        clientHandshake = offer.state
        sendClear(offer.frame)
    }

    func receiveHandshake(_ frame: Data) {
        guard let state = clientHandshake, !sessionReady else { return }
        guard let finished = SessionHandshake.clientFinish(token: pairingToken, state: state, reply: frame) else {
            setStatus(PadError.pairing.userMessage)
            return
        }
        sealLock.lock()
        outboundSeal = ChannelSeal(rawKey: finished.keys.padToHost, connectionID: state.party.connectionID)
        inboundSeal = SealInbox(rawKey: finished.keys.hostToPad)
        sessionReady = true
        sealLock.unlock()
        sendClear(finished.finish)
        onSessionKeys?(finished.keys, state.party.connectionID)
    }

    func sendClear(_ payload: Data) {
        guard let connection = connection else { return }
        connection.send(content: LengthPrefixedFraming.encode(payload), completion: .contentProcessed { _ in })
    }
}
