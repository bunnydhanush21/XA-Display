import AVFoundation
import CoreMedia
import Foundation
import Network
import UIKit
import XADisplayProtocol

extension VideoReceiver {
    func setConnected(_ connected: Bool, transport: TransportKind) {
        isConnected = connected
        self.transport = connected ? transport : .none
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.videoReceiver(self, connected: connected, transport: self.transport)
        }
        if !connected { setStatus(userPaused ? "Disconnected" : "Listening on :\(port)") }
    }
}
