import Foundation

/// Lets a UI or stats publisher run at a fixed rate. `force` bypasses the wait for phase changes.
public struct UIPace: Sendable {
    public var interval: TimeInterval
    private var last = Date.distantPast

    public init(interval: TimeInterval) {
        self.interval = interval
    }

    public mutating func allow(now: Date, force: Bool) -> Bool {
        if !force, now.timeIntervalSince(last) < interval { return false }
        last = now
        return true
    }
}

/// Keeps only the newest move until the display link drains it.
public struct CoalesceGate<T>: Sendable where T: Sendable {
    public private(set) var latest: T?

    public init() {}

    public mutating func offer(_ value: T) { latest = value }

    public mutating func take() -> T? {
        let value = latest
        latest = nil
        return value
    }
}
