import Foundation

/// Synthetic pacing and reconnect budgets. Device glass-to-glass numbers are not produced here.
public enum FramePacing {
    /// Population standard deviation of frame intervals, in milliseconds.
    public static func jitterMs(_ intervals: [Double]) -> Double {
        guard intervals.count > 1 else { return 0 }
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        let variance = intervals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(intervals.count)
        return variance.squareRoot()
    }
}

/// ReconnectBudget.
/// ReconnectBudget.
public enum ReconnectBudget {
    public static let limitSeconds = 2.0

    public static func withinBudget(_ elapsed: Double) -> Bool {
        elapsed >= 0 && elapsed < limitSeconds
    }
}
