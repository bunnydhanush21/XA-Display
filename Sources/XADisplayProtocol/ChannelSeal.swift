import CXASeal
@preconcurrency import CommonCrypto
import Foundation

/// Which socket a sealed frame belongs to. The name is AES-GCM associated data, so a video frame cannot be replayed on the input socket.
public enum SealChannel: String, Sendable {
    case video
    case input
    case udp

    public var aad: Data { Data(rawValue.utf8) }
}

/// Which way a frame travels. Each direction has its own HKDF key and its own nonce counter.
public enum SealDirection: String, Sendable {
    case hostToPad = "host-to-pad"
    case padToHost = "pad-to-host"
}

/// AES-256-GCM seal for one direction of a connection.
///
/// The key is HKDF-SHA256 of the pairing token. The 12-byte nonce is an 8-byte random connection id plus a counter.
/// A new seal draws a new connection id, so a reconnect does not reuse a nonce. This file does not implement a cipher.
public struct ChannelSeal: Sendable {
    public static let version: UInt8 = 1
    public static let nonceLength = 12
    public static let tagLength = 16
    public static let overhead = 1 + nonceLength + tagLength

    private let key: [UInt8]
    private let prefix: [UInt8]
    private var counter: UInt32

    public init(token: String, direction: SealDirection = .hostToPad) {
        self.init(token: token, direction: direction, connectionID: nil, counter: 0)
    }

    /// A key from the ECDH handshake. The pairing token is not an input.
    public init(rawKey: Data, connectionID: Data) {
        guard rawKey.count == Int(CC_SHA256_DIGEST_LENGTH), connectionID.count == 8 else {
            key = []
            prefix = []
            counter = 0
            return
        }
        key = [UInt8](rawKey)
        prefix = [UInt8](connectionID)
        counter = 0
    }

    init(token: String, direction: SealDirection, testingCounter: UInt32) {
        self.init(token: token, direction: direction, connectionID: [UInt8](repeating: 9, count: 8), counter: testingCounter)
    }

    private init(token: String, direction: SealDirection, connectionID: [UInt8]?, counter: UInt32) {
        let normalized = PairingGate.normalize(token)
        var resolved = connectionID ?? []
        if connectionID == nil, !normalized.isEmpty {
            var random = [UInt8](repeating: 0, count: 8)
            let status = random.withUnsafeMutableBytes { CCRandomGenerateBytes($0.baseAddress, 8) }
            if status == 0 { resolved = random }
        }
        guard !normalized.isEmpty, resolved.count == 8 else {
            key = []
            prefix = []
            self.counter = 0
            return
        }
        key = Self.derivedKey(token: normalized, direction: direction)
        prefix = resolved
        self.counter = counter
    }

    static func derivedKey(token: String, direction: SealDirection) -> [UInt8] {
        guard !token.isEmpty else { return [] }
        let ikm = Data(token.utf8)
        let salt = Data("xa-display-hkdf-v1".utf8)
        let info = Data("xa-display-aead-v1\n\(direction.rawValue)".utf8)
        return [UInt8](HKDF.derive(ikm: ikm, salt: salt, info: info, outputLength: Int(CC_SHA256_DIGEST_LENGTH)))
    }

    public mutating func seal(_ plaintext: Data, aad: Data) -> Data? {
        guard key.count == Int(CC_SHA256_DIGEST_LENGTH), let nonce = nextNonce() else { return nil }
        var out = Data(count: Self.overhead + plaintext.count)
        let wrote = out.withUnsafeMutableBytes { outRaw in
            key.withUnsafeBytes { keyRaw in
                nonce.withUnsafeBytes { nonceRaw in
                    plaintext.withUnsafeBytes { plainRaw in
                        aad.withUnsafeBytes { aadRaw in
                            SealBytes.seal(key: keyRaw, nonce: nonceRaw, aad: aadRaw, plaintext: plainRaw, output: outRaw)
                        }
                    }
                }
            }
        }
        guard wrote == out.count else { return nil }
        return out
    }

    /// Allocation-heavy decrypt kept so the throughput test can compare it with `open(into:)`.
    static func copyingOpen(key: [UInt8], sealed: Data, aad: Data) -> Data? {
        guard key.count == Int(CC_SHA256_DIGEST_LENGTH), sealed.count >= overhead, sealed.first == version else { return nil }
        let cipher = Data(sealed.dropFirst(1 + nonceLength).dropLast(tagLength))
        var tag = [UInt8](sealed.suffix(tagLength))
        var plain = [UInt8](repeating: 0, count: max(cipher.count, 1))
        let aadBytes = aad.isEmpty ? Data([0]) : aad
        let inputBytes = cipher.isEmpty ? Data([0]) : cipher
        let status = key.withUnsafeBytes { keyRaw in
            sealed.withUnsafeBytes { sealedRaw in
                aadBytes.withUnsafeBytes { aadRaw in
                    inputBytes.withUnsafeBytes { inputRaw in
                        plain.withUnsafeMutableBytes { outputRaw in
                            tag.withUnsafeMutableBytes { tagRaw in
                                xa_gcm_encrypt(
                                    keyRaw.bindMemory(to: UInt8.self).baseAddress, key.count,
                                    sealedRaw.bindMemory(to: UInt8.self).baseAddress?.advanced(by: 1), nonceLength,
                                    aadRaw.bindMemory(to: UInt8.self).baseAddress, aad.count,
                                    inputRaw.bindMemory(to: UInt8.self).baseAddress, cipher.count,
                                    outputRaw.bindMemory(to: UInt8.self).baseAddress,
                                    tagRaw.bindMemory(to: UInt8.self).baseAddress, tag.count,
                                    0
                                )
                            }
                        }
                    }
                }
            }
        }
        guard status == 0 else { return nil }
        return Data(plain.prefix(cipher.count))
    }

    public static func open(token: String, sealed: Data, aad: Data, direction: SealDirection = .hostToPad) -> Data? {
        decrypt(key: derivedKey(token: PairingGate.normalize(token), direction: direction), sealed: sealed, aad: aad)?.plain
    }

    static func decrypt(key: [UInt8], sealed: Data, aad: Data) -> (plain: Data, nonce: Data)? {
        var plain = Data()
        guard let nonce = open(key: key, sealed: sealed, aad: aad, into: &plain) else { return nil }
        return (plain, nonce)
    }

    /// Decrypts into `output`, reusing its storage when it is already large enough. Returns the nonce.
    static func open(key: [UInt8], sealed: Data, aad: Data, into output: inout Data) -> Data? {
        guard key.count == Int(CC_SHA256_DIGEST_LENGTH), sealed.count >= overhead, sealed.first == version else { return nil }
        let plainCount = sealed.count - overhead
        if output.count != plainCount {
            output.reserveCapacity(plainCount)
            output.count = plainCount
        }
        var nonce = Data()
        let ok = key.withUnsafeBytes { keyRaw -> Bool in
            sealed.withUnsafeBytes { sealedRaw -> Bool in
                aad.withUnsafeBytes { aadRaw -> Bool in
                    output.withUnsafeMutableBytes { outRaw -> Bool in
                        guard SealBytes.open(key: keyRaw, sealed: sealedRaw, aad: aadRaw, output: outRaw) != nil else { return false }
                        guard let base = sealedRaw.baseAddress else { return false }
                        nonce = Data(bytes: base.advanced(by: 1), count: nonceLength)
                        return true
                    }
                }
            }
        }
        return ok ? nonce : nil
    }

    private mutating func nextNonce() -> [UInt8]? {
        guard prefix.count == 8, counter < UInt32.max else { return nil }
        var nonce = prefix
        let value = counter
        counter += 1
        nonce.append(UInt8((value >> 24) & 0xFF))
        nonce.append(UInt8((value >> 16) & 0xFF))
        nonce.append(UInt8((value >> 8) & 0xFF))
        nonce.append(UInt8(value & 0xFF))
        return nonce
    }

}
