import Foundation

public struct WindowSnapshot: Equatable, Codable {
    public var id: Int
    public var ownerPID: Int
    public var title: String
    public var bounds: XARect
    public init(id: Int, ownerPID: Int, title: String, bounds: XARect) {
        self.id = id
        self.ownerPID = ownerPID
        self.title = title
        self.bounds = bounds
    }
}

public enum WindowRecovery {
    public static func stranded(_ windows: [WindowSnapshot], on display: XARect) -> [WindowSnapshot] {
        windows.filter { window in
            window.bounds.width > 1 && window.bounds.height > 1 && window.bounds.intersects(display)
        }
    }

    /// Moves a window that lived on the virtual display back onto the main display, keeping its relative origin.
    public static func relocate(_ window: WindowSnapshot, from display: XARect, to main: XARect) -> XARect {
        let relativeX = window.bounds.origin.x - display.origin.x
        let relativeY = window.bounds.origin.y - display.origin.y
        var x = main.origin.x + relativeX
        var y = main.origin.y + relativeY
        let maxX = main.maxX - min(window.bounds.width, main.width)
        let maxY = main.maxY - min(window.bounds.height, main.height)
        x = min(max(x, main.minX), max(maxX, main.minX))
        y = min(max(y, main.minY), max(maxY, main.minY))
        return XARect(origin: XAPoint(x: x, y: y), size: window.bounds.size)
    }
}

public struct LayoutWindow: Equatable, Codable {
    public var title: String
    public var owner: String
    public var relative: XARect
    public init(title: String, owner: String, relative: XARect) {
        self.title = title
        self.owner = owner
        self.relative = relative
    }
}

public struct LayoutSnapshot: Equatable, Codable {
    public var windows: [LayoutWindow]
    public init(windows: [LayoutWindow]) { self.windows = windows }
}

public enum LayoutMath {
    public static func relative(bounds: XARect, display: XARect) -> XARect {
        XARect(
            x: bounds.origin.x - display.origin.x,
            y: bounds.origin.y - display.origin.y,
            width: bounds.width,
            height: bounds.height
        )
    }
    public static func absolute(relative: XARect, display: XARect) -> XARect {
        XARect(
            x: display.origin.x + relative.origin.x,
            y: display.origin.y + relative.origin.y,
            width: relative.width,
            height: relative.height
        )
    }
}

public struct DiagnosticsSnapshot: Equatable, Codable {
    public var appVersion: String
    public var transport: String
    public var preset: String
    public var permissions: [String: Bool]
    public var pairingToken: String
    public var thermal: String
    public var battery: String
    public var notes: [String]
    public init(appVersion: String, transport: String, preset: String, permissions: [String: Bool], pairingToken: String, thermal: String, battery: String, notes: [String]) {
        self.appVersion = appVersion
        self.transport = transport
        self.preset = preset
        self.permissions = permissions
        self.pairingToken = pairingToken
        self.thermal = thermal
        self.battery = battery
        self.notes = notes
    }
}

public enum DiagnosticsText {
    public static let honesty = "Pointer input is injected as CGEvent mouse and keyboard events. It is not native macOS touchscreen input."

    public static func redactToken(_ token: String) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 2 { return "••••" }
        return "••••" + trimmed.suffix(2)
    }

    public static func render(_ snapshot: DiagnosticsSnapshot) -> String {
        var lines = [
            "XA Display diagnostics",
            "version: \(snapshot.appVersion)",
            "transport: \(snapshot.transport)",
            "preset: \(snapshot.preset)",
            "thermal: \(snapshot.thermal)",
            "battery: \(snapshot.battery)",
            "pairing: \(redactToken(snapshot.pairingToken))",
            "permissions:"
        ]
        for key in snapshot.permissions.keys.sorted() {
            lines.append("  \(key): \(snapshot.permissions[key] == true ? "granted" : "missing")")
        }
        if !snapshot.notes.isEmpty {
            lines.append("notes:")
            lines.append(contentsOf: snapshot.notes.map { "  \($0)" })
        }
        lines.append(honesty)
        lines.append("Capture→ack includes the return trip and is not a glass-to-glass measurement. Handoff is receive-to-enqueue on the iPad, not a decoder-callback duration.")
        return lines.joined(separator: "\n")
    }
}
