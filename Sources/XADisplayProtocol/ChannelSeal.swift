@preconcurrency import CommonCrypto
import Foundation

/// Which socket a sealed frame belongs to. The name is AES-GCM associated data, so a video frame cannot be replayed on the input socket.
public enum SealChannel: String, Sendable {
    case video
    case input
    case udp

    public var aad: Data { Data(rawValue.utf8) }
}

/// AES-256-GCM seal for one direction of a channel.
///
/// The key is SHA-256 of the pairing token under a fixed domain label, from CommonCrypto.
/// The 12-byte nonce is a 4-byte random prefix plus a counter. This file does not implement a cipher.
public struct ChannelSeal: Sendable {
    public static let version: UInt8 = 1
    public static let nonceLength = 12
    public static let tagLength = 16
    public static let overhead = 1 + nonceLength + tagLength

    private let key: [UInt8]
    private let prefix: [UInt8]
    private var counter: UInt64

    public init(token: String) {
        let normalized = PairingGate.normalize(token)
        guard !normalized.isEmpty else {
            key = []
            prefix = [UInt8](repeating: 0, count: 4)
            counter = 0
            return
        }
        var material = Array("xa-display-aead-v1\n".utf8)
        material.append(contentsOf: normalized.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        material.withUnsafeBytes { raw in
            digest.withUnsafeMutableBytes { digestBytes in
                _ = CC_SHA256(raw.baseAddress, CC_LONG(material.count), digestBytes.bindMemory(to: UInt8.self).baseAddress)
            }
        }
        key = digest
        var random = [UInt8](repeating: 0, count: 4)
        let status = random.withUnsafeMutableBytes { CCRandomGenerateBytes($0.baseAddress, 4) }
        prefix = status == 0 ? random : [UInt8](repeating: 1, count: 4)
        counter = 0
    }

    public mutating func seal(_ plaintext: Data, aad: Data) -> Data? {
        guard key.count == Int(CC_SHA256_DIGEST_LENGTH) else { return nil }
        let nonce = nextNonce()
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

    public static func open(token: String, sealed: Data, aad: Data) -> Data? {
        let box = ChannelSeal(token: token)
        guard box.key.count == Int(CC_SHA256_DIGEST_LENGTH) else { return nil }
        guard sealed.count >= overhead, sealed.first == version else { return nil }
        let nonceStart = 1
        let cipherStart = nonceStart + nonceLength
        let tagStart = sealed.count - tagLength
        guard tagStart >= cipherStart else { return nil }
        let nonce = [UInt8](sealed[nonceStart..<cipherStart])
        let cipher = sealed.subdata(in: cipherStart..<tagStart)
        var tag = [UInt8](sealed[tagStart..<sealed.count])
        var plain = [UInt8](repeating: 0, count: max(cipher.count, 1))
        let status = crypt(encrypt: false, key: box.key, nonce: nonce, aad: aad, input: cipher, output: &plain, tag: &tag)
        guard status == kCCSuccess else { return nil }
        return Data(plain.prefix(cipher.count))
    }

    private mutating func nextNonce() -> [UInt8] {
        var nonce = prefix
        var value = counter
        counter &+= 1
        for shift in stride(from: 56, through: 0, by: -8) {
            nonce.append(UInt8((value >> UInt64(shift)) & 0xFF))
        }
        return nonce
    }

    private static func crypt(encrypt: Bool, key: [UInt8], nonce: [UInt8], aad: Data, input: Data, output: inout [UInt8], tag: inout [UInt8]) -> CCCryptorStatus {
        let inputCount = input.count
        return key.withUnsafeBytes { keyBytes in
            nonce.withUnsafeBytes { nonceBytes in
                aad.withUnsafeBytes { aadBytes in
                    input.withUnsafeBytes { inputBytes in
                        output.withUnsafeMutableBytes { outputBytes in
                            tag.withUnsafeMutableBytes { tagBytes in
                                var unused: UInt8 = 0
                                let inputPointer = inputCount == 0 ? UnsafeRawPointer(&unused) : inputBytes.baseAddress
                                let outputPointer = inputCount == 0 ? UnsafeMutableRawPointer(&unused) : outputBytes.baseAddress
                                let aadPointer = aad.isEmpty ? UnsafeRawPointer(&unused) : aadBytes.baseAddress
                                if encrypt {
                                    return CCCryptorGCMOneshotEncrypt(
                                        CCAlgorithm(kCCAlgorithmAES),
                                        keyBytes.baseAddress, key.count,
                                        nonceBytes.baseAddress, nonce.count,
                                        aadPointer, aad.count,
                                        inputPointer, inputCount,
                                        outputPointer,
                                        tagBytes.baseAddress, tag.count
                                    )
                                }
                                return CCCryptorGCMOneshotDecrypt(
                                    CCAlgorithm(kCCAlgorithmAES),
                                    keyBytes.baseAddress, key.count,
                                    nonceBytes.baseAddress, nonce.count,
                                    aadPointer, aad.count,
                                    inputPointer, inputCount,
                                    outputPointer,
                                    tagBytes.baseAddress, tag.count
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
