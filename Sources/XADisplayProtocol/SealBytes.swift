import CXASeal
import Foundation

/// AES-GCM into caller-owned memory. The frame bytes are not copied into temporary arrays.
enum SealBytes {
    static func seal(key: UnsafeRawBufferPointer, nonce: UnsafeRawBufferPointer, aad: UnsafeRawBufferPointer, plaintext: UnsafeRawBufferPointer, output: UnsafeMutableRawBufferPointer) -> Int? {
        let total = ChannelSeal.overhead + plaintext.count
        guard key.count == 32, nonce.count == ChannelSeal.nonceLength, output.count >= total, let out = output.baseAddress else { return nil }
        var dummy: UInt8 = 0
        let plainPtr = plaintext.baseAddress ?? UnsafeRawPointer(&dummy)
        let aadPtr = aad.baseAddress ?? UnsafeRawPointer(&dummy)
        guard let keyPtr = key.baseAddress, let noncePtr = nonce.baseAddress else { return nil }
        out.storeBytes(of: ChannelSeal.version, as: UInt8.self)
        out.advanced(by: 1).copyMemory(from: noncePtr, byteCount: ChannelSeal.nonceLength)
        let status = xa_gcm_encrypt(
            keyPtr.assumingMemoryBound(to: UInt8.self), key.count,
            noncePtr.assumingMemoryBound(to: UInt8.self), nonce.count,
            aadPtr.assumingMemoryBound(to: UInt8.self), aad.count,
            plainPtr.assumingMemoryBound(to: UInt8.self), plaintext.count,
            out.advanced(by: 1 + ChannelSeal.nonceLength).assumingMemoryBound(to: UInt8.self),
            out.advanced(by: total - ChannelSeal.tagLength).assumingMemoryBound(to: UInt8.self),
            ChannelSeal.tagLength,
            1
        )
        return status == 0 ? total : nil
    }

    static func open(key: UnsafeRawBufferPointer, sealed: UnsafeRawBufferPointer, aad: UnsafeRawBufferPointer, output: UnsafeMutableRawBufferPointer) -> Int? {
        guard key.count == 32, sealed.count >= ChannelSeal.overhead, let sealedBase = sealed.baseAddress, sealedBase.load(as: UInt8.self) == ChannelSeal.version else { return nil }
        let plainCount = sealed.count - ChannelSeal.overhead
        guard output.count >= plainCount, let keyPtr = key.baseAddress else { return nil }
        var dummy: UInt8 = 0
        let outPtr = plainCount == 0 ? UnsafeMutableRawPointer(&dummy) : output.baseAddress
        guard let outPtr else { return nil }
        let aadPtr = aad.baseAddress ?? UnsafeRawPointer(&dummy)
        let cipher = sealedBase.advanced(by: 1 + ChannelSeal.nonceLength)
        let status = xa_gcm_encrypt(
            keyPtr.assumingMemoryBound(to: UInt8.self), key.count,
            sealedBase.advanced(by: 1).assumingMemoryBound(to: UInt8.self), ChannelSeal.nonceLength,
            aadPtr.assumingMemoryBound(to: UInt8.self), aad.count,
            plainCount == 0 ? UnsafeRawPointer(&dummy).assumingMemoryBound(to: UInt8.self) : cipher.assumingMemoryBound(to: UInt8.self),
            plainCount,
            outPtr.assumingMemoryBound(to: UInt8.self),
            UnsafeMutableRawPointer(mutating: sealedBase.advanced(by: sealed.count - ChannelSeal.tagLength)).assumingMemoryBound(to: UInt8.self),
            ChannelSeal.tagLength,
            0
        )
        return status == 0 ? plainCount : nil
    }
}
