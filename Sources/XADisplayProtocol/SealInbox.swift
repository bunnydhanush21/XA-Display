import Foundation

/// Remembers nonce counters for one direction so a sealed frame cannot be opened twice.
public struct SealInbox: Sendable {
    private let key: [UInt8]
    private var epochs: [UInt64: ReplayWindow] = [:]
    private var order: [UInt64] = []

    public init(token: String, direction: SealDirection) {
        key = ChannelSeal.derivedKey(token: PairingGate.normalize(token), direction: direction)
    }

    /// Opens frames sealed with a handshake key.
    public init(rawKey: Data) {
        key = rawKey.count == Int(CC_SHA256_DIGEST_LENGTH) ? [UInt8](rawKey) : []
    }

    public mutating func open(sealed: Data, aad: Data) -> Data? {
        guard let opened = ChannelSeal.decrypt(key: key, sealed: sealed, aad: aad) else { return nil }
        guard accept(opened.nonce) else { return nil }
        return opened.plain
    }

    private mutating func accept(_ nonce: Data) -> Bool {
        guard nonce.count == ChannelSeal.nonceLength else { return false }
        var epoch: UInt64 = 0
        for byte in nonce.prefix(8) { epoch = (epoch << 8) | UInt64(byte) }
        var counter: UInt32 = 0
        for byte in nonce.suffix(4) { counter = (counter << 8) | UInt32(byte) }
        if epochs[epoch] == nil {
            guard order.count < 64 else { return false }
            order.append(epoch)
            epochs[epoch] = ReplayWindow()
        }
        guard var window = epochs[epoch] else { return false }
        let accepted = window.accept(counter)
        epochs[epoch] = window
        return accepted
    }
}

struct ReplayWindow: Sendable {
    private var highest: UInt32?
    private var seen: Set<UInt32> = []

    mutating func accept(_ counter: UInt32) -> Bool {
        guard let highest else {
            self.highest = counter
            seen = [counter]
            return true
        }
        if counter > highest {
            let oldest = counter >= 63 ? counter - 63 : 0
            seen = seen.filter { $0 >= oldest }
            seen.insert(counter)
            self.highest = counter
            return true
        }
        if highest - counter >= 64 || seen.contains(counter) { return false }
        seen.insert(counter)
        return true
    }
}
