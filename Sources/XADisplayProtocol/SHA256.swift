import Foundation

enum SHA256Box {
    static func hash(_ message: [UInt8]) -> [UInt8] {
        var state: [UInt32] = [
            0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
            0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19
        ]
        var data = message
        let bitCount = UInt64(message.count) &* 8
        data.append(0x80)
        while data.count % 64 != 56 { data.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            data.append(UInt8((bitCount >> UInt64(shift)) & 0xFF))
        }
        var index = 0
        while index < data.count {
            var words = [UInt32](repeating: 0, count: 64)
            for word in 0..<16 {
                let base = index + word * 4
                words[word] =
                    (UInt32(data[base]) << 24) | (UInt32(data[base + 1]) << 16)
                    | (UInt32(data[base + 2]) << 8) | UInt32(data[base + 3])
            }
            for word in 16..<64 {
                let s0 = rotate(words[word - 15], 7) ^ rotate(words[word - 15], 18) ^ (words[word - 15] >> 3)
                let s1 = rotate(words[word - 2], 17) ^ rotate(words[word - 2], 19) ^ (words[word - 2] >> 10)
                words[word] = words[word - 16] &+ s0 &+ words[word - 7] &+ s1
            }
            var a = state[0]
            var b = state[1]
            var c = state[2]
            var d = state[3]
            var e = state[4]
            var f = state[5]
            var g = state[6]
            var h = state[7]
            for word in 0..<64 {
                let s1 = rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)
                let choice = (e & f) ^ (~e & g)
                let temp1 = h &+ s1 &+ choice &+ round[word] &+ words[word]
                let s0 = rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ majority
                h = g
                g = f
                f = e
                e = d &+ temp1
                d = c
                c = b
                b = a
                a = temp1 &+ temp2
            }
            state[0] = state[0] &+ a
            state[1] = state[1] &+ b
            state[2] = state[2] &+ c
            state[3] = state[3] &+ d
            state[4] = state[4] &+ e
            state[5] = state[5] &+ f
            state[6] = state[6] &+ g
            state[7] = state[7] &+ h
            index += 64
        }
        return state.flatMap { word in
            (0..<4).reversed().map { UInt8((word >> (UInt32($0) * 8)) & 0xFF) }
        }
    }

    private static func rotate(_ value: UInt32, _ count: UInt32) -> UInt32 {
        (value >> count) | (value << (32 - count))
    }

    private static let round: [UInt32] = [
        0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
        0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
        0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
        0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
        0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
        0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
        0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
        0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2
    ]
}

enum HMACSHA256 {
    static func digest(key: [UInt8], message: [UInt8]) -> [UInt8] {
        let block = 64
        var keyBytes = key
        if keyBytes.count > block { keyBytes = SHA256Box.hash(keyBytes) }
        if keyBytes.count < block { keyBytes.append(contentsOf: repeatElement(0, count: block - keyBytes.count)) }
        let oKey = keyBytes.map { $0 ^ 0x5C }
        let iKey = keyBytes.map { $0 ^ 0x36 }
        return SHA256Box.hash(oKey + SHA256Box.hash(iKey + message))
    }
}
