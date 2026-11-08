import Foundation

public enum ProtocolError: Error, Equatable {
    case truncated
    case badVersion
    case lengthMismatch
    case tooLarge
    case stringTooLong
    case badUTF8
    case badEnum
}

public struct ByteWriter {
    public private(set) var data = Data()
    public init() {}
    public mutating func u8(_ value: UInt8) { data.append(value) }
    public mutating func u16(_ value: UInt16) { appendInteger(value.bigEndian) }
    public mutating func u32(_ value: UInt32) { appendInteger(value.bigEndian) }
    public mutating func u64(_ value: UInt64) { appendInteger(value.bigEndian) }
    public mutating func f64(_ value: Double) { u64(value.bitPattern) }
    public mutating func bytes(_ value: Data) { data.append(value) }
    public mutating func str(_ value: String, maxBytes: Int = 2_048) throws {
        let utf = Array(value.utf8)
        guard utf.count <= maxBytes, utf.count <= Int(UInt16.max) else { throw ProtocolError.stringTooLong }
        u16(UInt16(utf.count))
        data.append(contentsOf: utf)
    }
    private mutating func appendInteger<T>(_ value: T) {
        var value = value
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }
}

public struct ByteReader {
    public let data: Data
    public var offset = 0
    public var remaining: Int { data.count - offset }
    public init(data: Data) { self.data = data }

    public mutating func u8() throws -> UInt8 {
        guard remaining >= 1 else { throw ProtocolError.truncated }
        defer { offset += 1 }
        return data[offset]
    }
    public mutating func u16() throws -> UInt16 {
        guard remaining >= 2 else { throw ProtocolError.truncated }
        let value = (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
        offset += 2
        return value
    }
    public mutating func u32() throws -> UInt32 {
        guard remaining >= 4 else { throw ProtocolError.truncated }
        let value =
            (UInt32(data[offset]) << 24) | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8) | UInt32(data[offset + 3])
        offset += 4
        return value
    }
    public mutating func u64() throws -> UInt64 {
        guard remaining >= 8 else { throw ProtocolError.truncated }
        var value: UInt64 = 0
        for index in 0..<8 {
            value = (value << 8) | UInt64(data[offset + index])
        }
        offset += 8
        return value
    }
    public mutating func f64() throws -> Double { Double(bitPattern: try u64()) }
    public mutating func str(maxBytes: Int = 2_048) throws -> String {
        let count = Int(try u16())
        guard count <= maxBytes else { throw ProtocolError.stringTooLong }
        guard count <= remaining else { throw ProtocolError.truncated }
        let slice = data.subdata(in: offset..<(offset + count))
        offset += count
        guard let string = String(data: slice, encoding: .utf8) else { throw ProtocolError.badUTF8 }
        return string
    }
}
