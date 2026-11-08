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
        var cipher = [UInt8](repeating: 0, count: max(plaintext.count, 1))
        var tag = [UInt8](repeating: 0, count: Self.tagLength)
        let status = Self.crypt(
            encrypt: true, key: key, nonce: nonce, aad: aad, input: plaintext, output: &cipher, tag: &tag
        )
        guard status == kCCSuccess else { return nil }
        var out = Data([Self.version])
        out.append(contentsOf: nonce)
        if plaintext.count > 0 { out.append(contentsOf: cipher.prefix(plaintext.count)) }
        out.append(contentsOf: tag)
        return out
    }

    public static func open(token: String, sealed: Data, aad: Data, direction: SealDirection = .hostToPad) -> Data? {
        decrypt(key: derivedKey(token: PairingGate.normalize(token), direction: direction), sealed: sealed, aad: aad)?.plain
    }

    static func decrypt(key: [UInt8], sealed: Data, aad: Data) -> (plain: Data, nonce: Data)? {
        guard key.count == Int(CC_SHA256_DIGEST_LENGTH) else { return nil }
        guard sealed.count >= overhead, sealed.first == version else { return nil }
        let nonceStart = 1
        let cipherStart = nonceStart + nonceLength
        let tagStart = sealed.count - tagLength
        guard tagStart >= cipherStart else { return nil }
        let nonce = Data(sealed[nonceStart..<cipherStart])
        let cipher = sealed.subdata(in: cipherStart..<tagStart)
        var tag = [UInt8](sealed[tagStart..<sealed.count])
        var plain = [UInt8](repeating: 0, count: max(cipher.count, 1))
        let status = crypt(encrypt: false, key: key, nonce: [UInt8](nonce), aad: aad, input: cipher, output: &plain, tag: &tag)
        guard status == kCCSuccess else { return nil }
        return (Data(plain.prefix(cipher.count)), nonce)
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

    private static func crypt(encrypt: Bool, key: [UInt8], nonce: [UInt8], aad: Data, input: Data, output: inout [UInt8], tag: inout [UInt8]) -> CCCryptorStatus {
        let aadBytes = aad.isEmpty ? Data([0]) : aad
        let inputBytes = input.isEmpty ? Data([0]) : input
        var localOutput = output
        var localTag = tag
        let keyCount = key.count
        let nonceCount = nonce.count
        let aadCount = aad.count
        let inputCount = input.count
        let tagCount = localTag.count
        let status = key.withUnsafeBytes { keyRaw in
            nonce.withUnsafeBytes { nonceRaw in
                aadBytes.withUnsafeBytes { aadRaw in
                    inputBytes.withUnsafeBytes { inputRaw in
                        localOutput.withUnsafeMutableBytes { outputRaw in
                            localTag.withUnsafeMutableBytes { tagRaw in
                                xa_gcm_encrypt(
                                    keyRaw.bindMemory(to: UInt8.self).baseAddress, keyCount,
                                    nonceRaw.bindMemory(to: UInt8.self).baseAddress, nonceCount,
                                    aadRaw.bindMemory(to: UInt8.self).baseAddress, aadCount,
                                    inputRaw.bindMemory(to: UInt8.self).baseAddress, inputCount,
                                    outputRaw.bindMemory(to: UInt8.self).baseAddress,
                                    tagRaw.bindMemory(to: UInt8.self).baseAddress, tagCount,
                                    encrypt ? 1 : 0
                                )
                            }
                        }
                    }
                }
            }
        }
        output = localOutput
        tag = localTag
        return CCCryptorStatus(status)
    }
}
