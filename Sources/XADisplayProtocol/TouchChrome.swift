import Foundation

public enum ResizeCorner: UInt8, Equatable {
    case topLeft = 1
    case topRight = 2
    case bottomLeft = 3
    case bottomRight = 4
}

public enum TileRegion: Equatable {
    case leftHalf, rightHalf, topLeft, topRight, bottomLeft, bottomRight
}

/// Title-bar and corner hits use the window frame, never the whole display.
public enum WindowChrome {
    public static let titleBarPoints = 28.0
    public static let minimumHit: Double = 36

    public static func titleBar(of window: XARect, height: Double = titleBarPoints) -> XARect {
        XARect(x: window.minX, y: window.minY, width: window.width, height: min(max(height, 1), window.height))
    }

    public static func window(containing point: XAPoint, windows: [XARect]) -> XARect? {
        windows.reversed().first { $0.contains(point) }
    }

    public static func isTitleBar(_ point: XAPoint, window: XARect, titleHeight: Double = titleBarPoints) -> Bool {
        titleBar(of: window, height: titleHeight).contains(point)
    }

    /// A double tap in the window body is a click, not a fill/restore.
    public static func isContent(point: XAPoint, window: XARect, titleHeight: Double = titleBarPoints) -> Bool {
        window.contains(point) && !isTitleBar(point, window: window, titleHeight: titleHeight)
    }

    public static func resizeCorner(point: XAPoint, window: XARect, handle: Double = minimumHit) -> ResizeCorner? {
        let size = max(handle, minimumHit)
        let corners: [(ResizeCorner, XAPoint)] = [
            (.topLeft, XAPoint(x: window.minX, y: window.minY)),
            (.topRight, XAPoint(x: window.maxX, y: window.minY)),
            (.bottomLeft, XAPoint(x: window.minX, y: window.maxY)),
            (.bottomRight, XAPoint(x: window.maxX, y: window.maxY)),
        ]
        return corners.first { _, origin in
            abs(point.x - origin.x) <= size && abs(point.y - origin.y) <= size
        }?.0
    }

    public static func anchor(window: XARect, corner: ResizeCorner) -> XAPoint {
        switch corner {
        case .topLeft: return XAPoint(x: window.minX, y: window.minY)
        case .topRight: return XAPoint(x: window.maxX, y: window.minY)
        case .bottomLeft: return XAPoint(x: window.minX, y: window.maxY)
        case .bottomRight: return XAPoint(x: window.maxX, y: window.maxY)
        }
    }
}

public enum FillToggle {
    public static func nearlyFills(_ window: XARect, display: XARect, slack: Double = 8) -> Bool {
        abs(window.minX - display.minX) <= slack && abs(window.minY - display.minY) <= slack
            && abs(window.width - display.width) <= slack && abs(window.height - display.height) <= slack
    }

    /// Double-tap the title bar fills the display, or restores the frame saved before the fill.
    public static func toggle(window: XARect, display: XARect, saved: XARect?) -> (frame: XARect, saved: XARect?) {
        if nearlyFills(window, display: display), let saved = saved {
            return (saved, nil)
        }
        return (display, window)
    }
}

public enum TitleBarFlick {
    public static func region(start: XAPoint, dx: Double, dy: Double, speed: Double, windows: [XARect], minimumSpeed: Double = 700) -> TileRegion? {
        guard speed >= minimumSpeed, let window = WindowChrome.window(containing: start, windows: windows),
              WindowChrome.isTitleBar(start, window: window) else { return nil }
        let horizontal = abs(dx) >= abs(dy)
        if horizontal && abs(dy) < 30 {
            return dx < 0 ? .leftHalf : .rightHalf
        }
        if dx < 0 && dy < 0 { return .topLeft }
        if dx >= 0 && dy < 0 { return .topRight }
        if dx < 0 { return .bottomLeft }
        return .bottomRight
    }
}

public enum WindowResize {
    public static func resized(window: XARect, corner: ResizeCorner, translation: XAPoint, minimum: Double = 120) -> XARect {
        var minX = window.minX
        var minY = window.minY
        var maxX = window.maxX
        var maxY = window.maxY
        switch corner {
        case .topLeft:
            minX += translation.x
            minY += translation.y
        case .topRight:
            maxX += translation.x
            minY += translation.y
        case .bottomLeft:
            minX += translation.x
            maxY += translation.y
        case .bottomRight:
            maxX += translation.x
            maxY += translation.y
        }
        if maxX - minX < minimum { maxX = minX + minimum }
        if maxY - minY < minimum { maxY = minY + minimum }
        return XARect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

public enum QuarterFrame {
    public static func frame(_ region: TileRegion, display: XARect) -> XARect {
        let halfW = display.width / 2
        let halfH = display.height / 2
        switch region {
        case .leftHalf:
            return XARect(x: display.minX, y: display.minY, width: halfW, height: display.height)
        case .rightHalf:
            return XARect(x: display.minX + halfW, y: display.minY, width: halfW, height: display.height)
        case .topLeft:
            return XARect(x: display.minX, y: display.minY, width: halfW, height: halfH)
        case .topRight:
            return XARect(x: display.minX + halfW, y: display.minY, width: halfW, height: halfH)
        case .bottomLeft:
            return XARect(x: display.minX, y: display.minY + halfH, width: halfW, height: halfH)
        case .bottomRight:
            return XARect(x: display.minX + halfW, y: display.minY + halfH, width: halfW, height: halfH)
        }
    }
}

public enum TitleBarDecision: Equatable {
    case click(XAPoint)
    case pending
    case fillToggle(XARect)
}

/// Title-bar taps wait for a second tap. Content taps click immediately and never fill the window.
public struct TitleBarArbiter {
    public var window: Double
    private var pendingPoint: XAPoint?
    private var pendingWindow: XARect?
    private var pendingTime = 0.0

    public init(window: Double = 0.35) { self.window = window }

    public mutating func tap(point: XAPoint, time: Double, windows: [XARect], titleHeight: Double = WindowChrome.titleBarPoints) -> TitleBarDecision {
        guard let hit = WindowChrome.window(containing: point, windows: windows),
              WindowChrome.isTitleBar(point, window: hit, titleHeight: titleHeight) else {
            pendingPoint = nil
            pendingWindow = nil
            return .click(point)
        }
        if let previous = pendingWindow, time - pendingTime <= window, previous.intersects(hit) {
            pendingPoint = nil
            pendingWindow = nil
            return .fillToggle(hit)
        }
        pendingPoint = point
        pendingWindow = hit
        pendingTime = time
        return .pending
    }

    public mutating func cancel() {
        pendingPoint = nil
        pendingWindow = nil
    }

    public mutating func flush(now: Double) -> TitleBarDecision? {
        guard let point = pendingPoint, now - pendingTime > window else { return nil }
        pendingPoint = nil
        pendingWindow = nil
        return .click(point)
    }
}

public struct TrafficTarget: Equatable {
    public var id: String
    public var rect: XARect
    public init(id: String, rect: XARect) {
        self.id = id
        self.rect = rect
    }
}

public enum TrafficLights {
    public static func targets(titleBar: XARect, minimum: Double = WindowChrome.minimumHit) -> [TrafficTarget] {
        let side = max(minimum, 36)
        let y = titleBar.minY + max(0, (titleBar.height - side) / 2)
        let names = ["close", "minimize", "zoom"]
        return names.enumerated().map { index, name in
            TrafficTarget(id: name, rect: XARect(x: titleBar.minX + 8 + Double(index) * (side + 6), y: y, width: side, height: side))
        }
    }
}

public struct CursorNudge {
    public static func apply(point: XAPoint, offset: XAPoint) -> XAPoint {
        XAPoint(x: point.x + offset.x, y: point.y + offset.y)
    }
}

public enum EdgeSystemAction: String, Equatable, Codable, CaseIterable {
    case notificationCenter
    case missionControl
    case appExpose
    case launchpad
    case controlCenter

    public var shortcut: KeyShortcut {
        switch self {
        case .notificationCenter:
            return KeyShortcut(input: "", modifiers: [])
        case .missionControl:
            return KeyShortcut(input: "UIKeyInputUpArrow", modifiers: .control)
        case .appExpose:
            return KeyShortcut(input: "UIKeyInputDownArrow", modifiers: .control)
        case .launchpad:
            return KeyShortcut(input: "UIKeyInputF4", modifiers: [])
        case .controlCenter:
            return KeyShortcut(input: "", modifiers: [])
        }
    }

    public var windowAction: WindowAction {
        switch self {
        case .notificationCenter: return .notificationCenter
        case .missionControl: return .missionControl
        case .appExpose: return .appExpose
        case .launchpad: return .launchpad
        case .controlCenter: return .controlCenter
        }
    }
}

public enum EdgeDrawerGate {
    /// Right-edge swipe toward the center. The left edge stays free for the sidebar and iOS.
    public static func shouldOpen(startX: Double, viewWidth: Double, translationX: Double, minimumTravel: Double = 36) -> Bool {
        guard viewWidth > 80 else { return false }
        return startX >= viewWidth - 28 && translationX <= -minimumTravel
    }
}

public struct AppZoomBinding: Equatable, Codable {
    public var bundleID: String
    public var zoomIn: String
    public var zoomOut: String
    public var modifiers: UInt8
    public init(bundleID: String, zoomIn: String, zoomOut: String, modifiers: UInt8) {
        self.bundleID = bundleID
        self.zoomIn = zoomIn
        self.zoomOut = zoomOut
        self.modifiers = modifiers
    }

    public static let universal = AppZoomBinding(bundleID: "*", zoomIn: "=", zoomOut: "-", modifiers: XAModifierMask.command.rawValue)
}

public enum ZoomProfiles {
    public static func resolve(bundleID: String, bindings: [AppZoomBinding]) -> AppZoomBinding {
        if let match = bindings.first(where: { $0.bundleID == bundleID }) { return match }
        if let any = bindings.first(where: { $0.bundleID == "*" }) { return any }
        return .universal
    }
}

public enum MacTouchScroll {
    /// Local inertia only. Steps keep the finger direction and stop. No rubber-band reversal.
    public static func steps(velocityX: Double, velocityY: Double) -> [InertiaStep] {
        let raw = ScrollInertia.steps(velocityX: velocityX, velocityY: velocityY, friction: 0.84, minSpeed: 0.35, maxSteps: 18)
        let signX = velocityX == 0 ? 0 : (velocityX > 0 ? 1.0 : -1.0)
        let signY = velocityY == 0 ? 0 : (velocityY > 0 ? 1.0 : -1.0)
        return raw.filter { step in
            (signX == 0 || step.dx == 0 || (step.dx > 0) == (signX > 0))
                && (signY == 0 || step.dy == 0 || (step.dy > 0) == (signY > 0))
        }
    }
}

public enum RepeatGate {
    public static func allow(now: Double, last: Double?, interval: Double) -> Bool {
        guard let last = last else { return true }
        return now - last >= max(0, interval)
    }
}

public enum TouchMetrics {
    public static func target(requested: Double, large: Bool) -> Double {
        max(WindowChrome.minimumHit, large ? max(requested, 52) : requested)
    }
}

public struct EdgeBinding: Equatable, Codable {
    public var action: EdgeSystemAction
    public var input: String
    public var modifiers: UInt8
    public init(action: EdgeSystemAction, input: String, modifiers: UInt8) {
        self.action = action
        self.input = input
        self.modifiers = modifiers
    }
}

public enum EdgeRoute: Equatable {
    case key(KeyShortcut)
    case accessibility
}

public enum EdgeRouter {
    /// A configured key is posted as a normal shortcut. An empty key asks the host to use Accessibility.
    public static func route(_ binding: EdgeBinding) -> EdgeRoute {
        guard !binding.input.isEmpty else { return .accessibility }
        return .key(KeyShortcut(input: binding.input, modifiers: XAModifierMask(rawValue: binding.modifiers)))
    }
}

public enum ChromeWire {
    public static func normalized(_ frame: XARect, in display: XARect) -> XARect {
        guard display.width > 0, display.height > 0 else { return XARect(x: 0, y: 0, width: 0, height: 0) }
        return XARect(
            x: (frame.minX - display.minX) / display.width,
            y: (frame.minY - display.minY) / display.height,
            width: frame.width / display.width,
            height: frame.height / display.height
        )
    }

    public static func windows(_ rects: [XARect]) -> String {
        rects.prefix(16).map { rect in
            String(format: "%.5f,%.5f,%.5f,%.5f", rect.minX, rect.minY, rect.width, rect.height)
        }.joined(separator: ";")
    }

    public static func parseWindows(_ text: String) -> [XARect] {
        guard !text.isEmpty else { return [] }
        return text.split(separator: ";").compactMap { part in
            let numbers = part.split(separator: ",").compactMap { Double($0) }
            guard numbers.count == 4, numbers.allSatisfy({ $0.isFinite }) else { return nil }
            return XARect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        }
    }

    public static func menus(_ titles: [String]) -> String {
        titles.prefix(40).map { title in
            title.replacingOccurrences(of: "\u{1e}", with: " ").replacingOccurrences(of: "\n", with: " ")
        }.joined(separator: "\u{1e}")
    }

    public static func parseMenus(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        return text.split(separator: "\u{1e}", omittingEmptySubsequences: true).map(String.init)
    }
}

public struct TouchAssist: Equatable, Codable {
    public var windowChrome: Bool
    public var loupeWhileDragging: Bool
    public var cursorOffsetX: Double
    public var cursorOffsetY: Double
    public var trafficLights: Bool
    public var menuOverlay: Bool
    public var edgeDrawer: Bool
    public var largeButtons: Bool
    public var ignoreRepeat: Double
    public var zoomBindings: [AppZoomBinding]
    public var edgeBindings: [EdgeBinding]

    public static let defaultEdges: [EdgeBinding] = [
        EdgeBinding(action: .missionControl, input: "UIKeyInputUpArrow", modifiers: XAModifierMask.control.rawValue),
        EdgeBinding(action: .appExpose, input: "UIKeyInputDownArrow", modifiers: XAModifierMask.control.rawValue),
        EdgeBinding(action: .launchpad, input: "UIKeyInputF4", modifiers: 0),
        EdgeBinding(action: .notificationCenter, input: "", modifiers: 0),
        EdgeBinding(action: .controlCenter, input: "", modifiers: 0),
    ]

    public init(
        windowChrome: Bool = true,
        loupeWhileDragging: Bool = true,
        cursorOffsetX: Double = 0,
        cursorOffsetY: Double = 0,
        trafficLights: Bool = true,
        menuOverlay: Bool = false,
        edgeDrawer: Bool = true,
        largeButtons: Bool = true,
        ignoreRepeat: Double = 0.28,
        zoomBindings: [AppZoomBinding] = [.universal],
        edgeBindings: [EdgeBinding] = TouchAssist.defaultEdges
    ) {
        self.windowChrome = windowChrome
        self.loupeWhileDragging = loupeWhileDragging
        self.cursorOffsetX = cursorOffsetX
        self.cursorOffsetY = cursorOffsetY
        self.trafficLights = trafficLights
        self.menuOverlay = menuOverlay
        self.edgeDrawer = edgeDrawer
        self.largeButtons = largeButtons
        self.ignoreRepeat = ignoreRepeat
        self.zoomBindings = zoomBindings
        self.edgeBindings = edgeBindings
    }

    public func binding(for action: EdgeSystemAction) -> EdgeBinding {
        edgeBindings.first { $0.action == action }
            ?? TouchAssist.defaultEdges.first { $0.action == action }
            ?? EdgeBinding(action: action, input: "", modifiers: 0)
    }
}
