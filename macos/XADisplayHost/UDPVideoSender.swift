import Foundation
import Network
import XADisplayProtocol

final class UDPVideoSender {
    private var connection: NWConnection?
    private var recent: [UInt16: Data] = [:]
    private let queue = DispatchQueue(label: "xa.udp.send")

    func connect(host: String) {
        connection?.cancel()
        let params = NWParameters.udp
        params.serviceClass = .interactiveVideo
        let port = NWEndpoint.Port(rawValue: XADisplayProtocolInfo.udpVideoPort) ?? .any
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: params)
        connection.start(queue: queue)
        self.connection = connection
    }

    func send(_ packets: [UDPVideoPacket]) {
        for packet in packets {
            let data = packet.encode()
            recent[packet.sequence] = data
            connection?.send(content: data, completion: .contentProcessed { _ in })
        }
        if recent.count > 160 {
            let stale = recent.keys.sorted { Int16(bitPattern: $1 &- $0) > 0 }.prefix(recent.count - 128)
            for key in stale { recent[key] = nil }
        }
    }

    func retransmit(_ sequences: [UInt16]) {
        for sequence in sequences {
            guard let data = recent[sequence] else { continue }
            connection?.send(content: data, completion: .contentProcessed { _ in })
        }
    }

    func stop() {
        connection?.cancel()
        connection = nil
    }
}
