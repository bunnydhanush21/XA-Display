@preconcurrency import CommonCrypto
import Foundation

/// HKDF-SHA256 (RFC 5869) using CommonCrypto HMAC. This file does not implement a hash.
public enum HKDF {
    public static func derive(ikm: Data, salt: Data, info: Data, outputLength: Int) -> Data {
        let prk = hmac(key: salt, message: ikm)
        var okm = Data()
        var previous = Data()
        var counter: UInt8 = 1
        while okm.count < outputLength {
            var block = previous
            block.append(info)
            block.append(counter)
            previous = hmac(key: prk, message: block)
            okm.append(previous)
            if counter == .max { break }
            counter += 1
        }
        return Data(okm.prefix(outputLength))
    }

    static func hmac(key: Data, message: Data) -> Data {
        var mac = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        let keyCount = key.count
        let messageCount = message.count
        key.withUnsafeBytes { keyRaw in
            message.withUnsafeBytes { messageRaw in
                mac.withUnsafeMutableBytes { macRaw in
                    CCHmac(
                        CCHmacAlgorithm(kCCHmacAlgSHA256),
                        keyRaw.baseAddress, keyCount,
                        messageRaw.baseAddress, messageCount,
                        macRaw.baseAddress
                    )
                }
            }
        }
        return Data(mac)
    }
}
