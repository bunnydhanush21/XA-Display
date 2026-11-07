import Foundation

public enum XADisplayProtocolInfo {
    public static let inputVersion: UInt16 = 1
    /// Length-prefixed video and legacy JSON. The iPad listens; the Mac connects.
    public static let videoPort: UInt16 = 9000
    /// Versioned input channel. Injection requires a paired token and session.
    public static let inputPort: UInt16 = 9001
    public static let bonjourType = "_opensidecar._tcp"
}

public struct XAPoint: Equatable, Codable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
    public static let zero = XAPoint(x: 0, y: 0)
}

public struct XASize: Equatable, Codable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
    public static let zero = XASize(width: 0, height: 0)
}

public struct XARect: Equatable, Codable {
    public var origin: XAPoint
    public var size: XASize
    public init(origin: XAPoint, size: XASize) {
        self.origin = origin
        self.size = size
    }
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.origin = XAPoint(x: x, y: y)
        self.size = XASize(width: width, height: height)
    }
    public var minX: Double { origin.x }
    public var minY: Double { origin.y }
    public var maxX: Double { origin.x + size.width }
    public var maxY: Double { origin.y + size.height }
    public var width: Double { size.width }
    public var height: Double { size.height }

    public func intersects(_ other: XARect) -> Bool {
        minX < other.maxX && maxX > other.minX && minY < other.maxY && maxY > other.minY
    }

    public func contains(_ point: XAPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }
}

public struct XAModifierMask: OptionSet, Equatable, Hashable, Codable {
    public var rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let shift = XAModifierMask(rawValue: 1)
    public static let control = XAModifierMask(rawValue: 2)
    public static let option = XAModifierMask(rawValue: 4)
    public static let command = XAModifierMask(rawValue: 8)

    public var individualBits: [XAModifierMask] {
        [Self.shift, .control, .option, .command].filter { contains($0) }
    }
}

public enum MacKeyCode {
    public static let escape: UInt16 = 53
    public static let delete: UInt16 = 51
    public static let `return`: UInt16 = 36
    public static let tab: UInt16 = 48
    public static let space: UInt16 = 49
    public static let leftArrow: UInt16 = 123
    public static let rightArrow: UInt16 = 124
    public static let downArrow: UInt16 = 125
    public static let upArrow: UInt16 = 126
    public static let command: UInt16 = 55
    public static let shift: UInt16 = 56
    public static let option: UInt16 = 58
    public static let control: UInt16 = 59

    public static func letter(_ character: Character) -> UInt16? {
        switch character.lowercased() {
        case "a": return 0
        case "s": return 1
        case "d": return 2
        case "f": return 3
        case "h": return 4
        case "g": return 5
        case "z": return 6
        case "x": return 7
        case "c": return 8
        case "v": return 9
        case "b": return 11
        case "q": return 12
        case "w": return 13
        case "e": return 14
        case "r": return 15
        case "y": return 16
        case "t": return 17
        case "o": return 31
        case "u": return 32
        case "i": return 34
        case "p": return 35
        case "l": return 37
        case "j": return 38
        case "k": return 40
        case "n": return 45
        case "m": return 46
        default: return nil
        }
    }

    public static func digit(_ character: Character) -> UInt16? {
        switch character {
        case "1": return 18
        case "2": return 19
        case "3": return 20
        case "4": return 21
        case "5": return 23
        case "6": return 22
        case "7": return 26
        case "8": return 28
        case "9": return 25
        case "0": return 29
        default: return nil
        }
    }
}

public extension Int32 {
    static func clampingRounded(_ value: Double) -> Int32 {
        guard value.isFinite else { return 0 }
        let rounded = value.rounded()
        if rounded >= Double(Int32.max) { return Int32.max }
        if rounded <= Double(Int32.min) { return Int32.min }
        return Int32(rounded)
    }
}

public func xaHypot(_ x: Double, _ y: Double) -> Double {
    (x * x + y * y).squareRoot()
}
