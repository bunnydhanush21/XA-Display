import Foundation

/// SavedMac.
public struct SavedMac: Equatable, Codable {
    public var id: String
    public var name: String
    public var token: String
    public var lastUsed: Double

    public init(id: String, name: String, token: String, lastUsed: Double) {
        self.id = id
        self.name = name
        self.token = token
        self.lastUsed = lastUsed
    }
}

/// MacDirectory.
public struct MacDirectory: Equatable, Codable {
    public var macs: [SavedMac]
    public var lastID: String?

    public init(macs: [SavedMac] = [], lastID: String? = nil) {
        self.macs = macs
        self.lastID = lastID
    }

    public func last() -> SavedMac? {
        if let lastID = lastID, let match = macs.first(where: { $0.id == lastID }) { return match }
        return macs.max { $0.lastUsed < $1.lastUsed }
    }

    public func sorted() -> [SavedMac] {
        macs.sorted { $0.lastUsed > $1.lastUsed }
    }

    public mutating func remember(_ mac: SavedMac) {
        macs.removeAll { $0.id == mac.id }
        macs.append(mac)
        lastID = mac.id
    }

    public mutating func select(_ id: String, now: Double) {
        guard let index = macs.firstIndex(where: { $0.id == id }) else { return }
        macs[index].lastUsed = now
        lastID = id
    }

    public mutating func remove(_ id: String) {
        macs.removeAll { $0.id == id }
        if lastID == id { lastID = macs.max { $0.lastUsed < $1.lastUsed }?.id }
    }
}

/// LaunchRoute.
public enum LaunchRoute: Equatable {
    case resume(SavedMac)
    case picker
    case listen

    /// Home-screen launch with one-tap on goes straight to the last Mac.
    public static func decide(oneTap: Bool, directory: MacDirectory) -> LaunchRoute {
        if oneTap, let last = directory.last() { return .resume(last) }
        if directory.macs.count > 1 { return .picker }
        return .listen
    }
}

/// Wake is a Bonjour connection to the host service. There is no magic packet.
public enum WakeOnDemandPolicy {
    public static let usesMagicPacket = false
    public static let serviceType = XADisplayProtocolInfo.hostBonjourType
    public static let summary = """
        The iPad opens a TCP connection to the Mac's _xahost._tcp service. macOS can wake for that \
        connection when Wake for network access is on and a Bonjour Sleep Proxy is on the network. \
        XA Display does not send Wake-on-LAN magic packets. A Mac that is powered off, or whose host \
        was not running before sleep, will not wake.
        """
}
