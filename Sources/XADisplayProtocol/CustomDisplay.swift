import Foundation

/// CustomDisplaySettings.
public struct CustomDisplaySettings: Equatable, Codable {
    public var enabled: Bool
    public var width: Int
    public var height: Int
    public var fps: Int
    public var bitrate: Int

    public init(enabled: Bool = false, width: Int = 1440, height: Int = 1080, fps: Int = 30, bitrate: Int = 6_000_000) {
        self.enabled = enabled
        self.width = width
        self.height = height
        self.fps = fps
        self.bitrate = bitrate
    }

    public func clamped() -> CustomDisplaySettings {
        var copy = self
        copy.width = min(4096, max(640, width))
        copy.height = min(4096, max(480, height))
        copy.fps = min(60, max(10, fps))
        copy.bitrate = min(20_000_000, max(500_000, bitrate))
        return copy
    }

    public func applying(to preset: StreamPreset) -> StreamPreset {
        guard enabled else { return preset }
        let safe = clamped()
        var copy = preset
        copy.width = safe.width
        copy.height = safe.height
        copy.fps = safe.fps
        copy.bitrateUSB = safe.bitrate
        copy.bitrateWiFi = safe.bitrate
        return copy
    }
}

/// LogRing.
public struct LogRing: Equatable {
    public static let capacity = 200
    public private(set) var entries: [String] = []

    public init() {}

    public mutating func append(_ line: String) {
        let clean = Self.redact(line)
        guard !clean.isEmpty else { return }
        entries.append(clean)
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
    }

    public static func redact(_ line: String) -> String {
        var text = line
        let tokenPattern = try? NSRegularExpression(pattern: "\\b[A-HJ-NP-Z2-9]{4}-?[A-HJ-NP-Z2-9]{4}\\b")
        if let tokenPattern {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = tokenPattern.stringByReplacingMatches(in: text, range: range, withTemplate: "••••")
        }
        return text.replacingOccurrences(of: "pairing token ", with: "pairing ")
    }
}

/// StoredZip.
public enum StoredZip {
    public static func archive(name: String, data: Data) -> Data {
        let fileName = Array(name.utf8)
        var local = Data([0x50, 0x4B, 0x03, 0x04, 0, 0, 0, 0, 0, 0, 0, 0])
        local.append(contentsOf: [0, 0, 0, 0])
        local.append(contentsOf: le32(UInt32(data.count)))
        local.append(contentsOf: le32(UInt32(data.count)))
        local.append(contentsOf: le16(UInt16(fileName.count)))
        local.append(contentsOf: le16(0))
        local.append(contentsOf: fileName)
        local.append(data)
        let centralOffset = UInt32(local.count)
        var central = Data([0x50, 0x4B, 0x01, 0x02, 20, 0, 0, 0, 0, 0, 0, 0])
        central.append(contentsOf: [0, 0, 0, 0])
        central.append(contentsOf: le32(UInt32(data.count)))
        central.append(contentsOf: le32(UInt32(data.count)))
        central.append(contentsOf: le16(UInt16(fileName.count)))
        central.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        central.append(contentsOf: le32(0))
        central.append(contentsOf: fileName)
        var end = Data([0x50, 0x4B, 0x05, 0x06, 0, 0, 0, 0])
        end.append(contentsOf: le16(1))
        end.append(contentsOf: le16(1))
        end.append(contentsOf: le32(UInt32(central.count)))
        end.append(contentsOf: le32(centralOffset))
        end.append(contentsOf: le16(0))
        var result = local
        result.append(central)
        result.append(end)
        return result
    }

    private static func le16(_ value: UInt16) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8)] }
    private static func le32(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
    }
}

/// StatsPill.
public enum StatsPill {
    public static func heightFits(pill: Double, screen: Double) -> Bool {
        screen > 0 && pill / screen <= 0.04
    }
}
