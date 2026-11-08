import AVFoundation
import UIKit
import XADisplayProtocol

extension ReceiverViewController {
    func inputChannel(_ channel: InputChannel, roundTripMs: Double) {
        rttMs = roundTripMs
        refreshStats()
    }
    func inputChannel(_ channel: InputChannel, clockOffsetClientMinusHost: Double) {
        audio.setClockOffset(clockOffsetClientMinusHost)
    }
    func inputChannel(_ channel: InputChannel, nowPlaying: XANowPlaying) {
        mediaPanel?.show(nowPlaying)
    }
}
