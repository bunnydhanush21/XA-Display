import Foundation

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
        EdgeBinding(action: .controlCenter, input: "", modifiers: 0)
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
