import Foundation

public enum PointSpace: Equatable {
    case viewPoints
    case pixels
}

public enum XARotation: Int, Equatable {
    case identity = 0
    case clockwise90 = 90
    case clockwise180 = 180
    case clockwise270 = 270
}

public struct MapRequest: Equatable {
    public var point: XAPoint
    public var pointSpace: PointSpace
    public var viewSizePoints: XASize
    public var pixelsPerPoint: Double
    public var videoPixelSize: XASize
    public var rotation: XARotation
    public init(point: XAPoint, pointSpace: PointSpace, viewSizePoints: XASize, pixelsPerPoint: Double, videoPixelSize: XASize, rotation: XARotation) {
        self.point = point
        self.pointSpace = pointSpace
        self.viewSizePoints = viewSizePoints
        self.pixelsPerPoint = pixelsPerPoint
        self.videoPixelSize = videoPixelSize
        self.rotation = rotation
    }
}

public enum CoordinateMapper {
    public static func contentRect(view: XASize, video: XASize) -> XARect {
        guard video.width > 0, video.height > 0, view.width > 0, view.height > 0 else {
            return XARect(origin: .zero, size: view)
        }
        let videoAspect = video.width / video.height
        let viewAspect = view.width / view.height
        if videoAspect > viewAspect {
            let height = view.width / videoAspect
            let y = (view.height - height) / 2
            return XARect(x: 0, y: y, width: view.width, height: height)
        }
        let width = view.height * videoAspect
        let x = (view.width - width) / 2
        return XARect(x: x, y: 0, width: width, height: view.height)
    }

    /// Maps a touch into normalized video space. Returns nil when the point lands in a letterbox bar.
    /// Rotation converts a point on the displayed image back into virtual-display framebuffer space.
    public static func normalize(_ request: MapRequest) -> XAPoint? {
        var point = request.point
        if request.pointSpace == .pixels {
            guard request.pixelsPerPoint > 0 else { return nil }
            point.x /= request.pixelsPerPoint
            point.y /= request.pixelsPerPoint
        }
        let rect = contentRect(view: request.viewSizePoints, video: request.videoPixelSize)
        guard rect.width > 0, rect.height > 0 else { return nil }
        let slack = 0.01
        if point.x < rect.minX - slack || point.y < rect.minY - slack || point.x > rect.maxX + slack || point.y > rect.maxY + slack {
            return nil
        }
        let clampedX = min(max(point.x, rect.minX), rect.maxX)
        let clampedY = min(max(point.y, rect.minY), rect.maxY)
        let normalized = XAPoint(
            x: (clampedX - rect.minX) / rect.width,
            y: (clampedY - rect.minY) / rect.height
        )
        return rotate(normalized, request.rotation)
    }

    public static func rotate(_ point: XAPoint, _ rotation: XARotation) -> XAPoint {
        switch rotation {
        case .identity:
            return point
        case .clockwise90:
            return XAPoint(x: point.y, y: 1 - point.x)
        case .clockwise180:
            return XAPoint(x: 1 - point.x, y: 1 - point.y)
        case .clockwise270:
            return XAPoint(x: 1 - point.y, y: point.x)
        }
    }

    public static func globalPoint(normalized: XAPoint, displayFrame: XARect) -> XAPoint {
        XAPoint(
            x: displayFrame.origin.x + normalized.x * displayFrame.width,
            y: displayFrame.origin.y + normalized.y * displayFrame.height
        )
    }

    public static func scrollPixels(viewDelta: XAPoint, contentSize: XASize, videoPixelSize: XASize) -> XAPoint {
        guard contentSize.width > 0, contentSize.height > 0 else { return .zero }
        return XAPoint(
            x: viewDelta.x * (videoPixelSize.width / contentSize.width),
            y: viewDelta.y * (videoPixelSize.height / contentSize.height)
        )
    }
}

public enum ScrollWheelSign {
    /// Positive `contentDownPixels` means the document should move down (fingers moved down).
    /// CGEvent pixel wheel1 is positive when content moves up, so the sign flips.
    public static func wheel1(contentDownPixels: Double) -> Int32 {
        Int32.clampingRounded(-contentDownPixels)
    }
    public static func wheel2(contentRightPixels: Double) -> Int32 {
        Int32.clampingRounded(-contentRightPixels)
    }
}

public struct InertiaStep: Equatable {
    public var dx: Double
    public var dy: Double
    public init(dx: Double, dy: Double) {
        self.dx = dx
        self.dy = dy
    }
}

public enum ScrollInertia {
    public static func steps(velocityX: Double, velocityY: Double, friction: Double = 0.86, minSpeed: Double = 0.5, maxSteps: Int = 24) -> [InertiaStep] {
        guard friction > 0, friction < 1, maxSteps > 0 else { return [] }
        var x = velocityX
        var y = velocityY
        var out: [InertiaStep] = []
        for _ in 0..<maxSteps {
            x *= friction
            y *= friction
            if xaHypot(x, y) < minSpeed { break }
            out.append(InertiaStep(dx: x, dy: y))
        }
        return out
    }
}

public struct TouchSample: Equatable {
    public enum Phase: Equatable { case began, moved, ended, cancelled }
    public var time: Double
    public var phase: Phase
    public var location: XAPoint
    public var activeTouches: Int
    public init(time: Double, phase: Phase, location: XAPoint, activeTouches: Int) {
        self.time = time
        self.phase = phase
        self.location = location
        self.activeTouches = activeTouches
    }
}

public enum FingerGesture: Equatable {
    public enum DragPhase: Equatable { case began, moved, ended }
    case tap(XAPoint)
    case doubleTap(XAPoint)
    case longPress(XAPoint)
    case drag(DragPhase, XAPoint)
    case twoFingerTap(XAPoint)
    case twoFingerLongPress(XAPoint)
    case scroll(dx: Double, dy: Double, inertia: Bool)
    case relativeMove(dx: Double, dy: Double)
    case relativeClick(XAMouseButton)
}

public struct DirectTouchInterpreter {
    public var slop: Double
    public var doubleTapWindow: Double
    public var longPressDuration: Double
    private var origin: XAPoint?
    private var startTime: Double = 0
    private var moved = false
    private var dragging = false
    private var lastNorm: XAPoint?
    private var lastTapTime = -10.0
    private var lastTapPoint = XAPoint.zero

    public init(slop: Double = 12, doubleTapWindow: Double = 0.35, longPressDuration: Double = 0.45) {
        self.slop = slop
        self.doubleTapWindow = doubleTapWindow
        self.longPressDuration = longPressDuration
    }

    public mutating func feed(_ sample: TouchSample, normalize: (XAPoint) -> XAPoint?) -> [FingerGesture] {
        if sample.activeTouches >= 2 {
            return cancelDrag(normalize: normalize)
        }
        switch sample.phase {
        case .began:
            origin = sample.location
            startTime = sample.time
            moved = false
            dragging = false
            lastNorm = normalize(sample.location)
            return []
        case .moved:
            guard let origin else { return [] }
            if xaHypot(sample.location.x - origin.x, sample.location.y - origin.y) > slop {
                moved = true
            }
            guard moved else { return [] }
            var gestures: [FingerGesture] = []
            if !dragging {
                dragging = true
                if let start = lastNorm ?? normalize(origin) {
                    gestures.append(.drag(.began, start))
                }
            }
            if let point = normalize(sample.location) {
                lastNorm = point
                gestures.append(.drag(.moved, point))
            }
            return gestures
        case .ended:
            return finish(sample: sample, cancelled: false, normalize: normalize)
        case .cancelled:
            return finish(sample: sample, cancelled: true, normalize: normalize)
        }
    }

    private mutating func cancelDrag(normalize: (XAPoint) -> XAPoint?) -> [FingerGesture] {
        defer {
            origin = nil
            moved = false
            dragging = false
        }
        if dragging, let point = lastNorm {
            return [.drag(.ended, point)]
        }
        _ = normalize
        return []
    }

    private mutating func finish(sample: TouchSample, cancelled: Bool, normalize: (XAPoint) -> XAPoint?) -> [FingerGesture] {
        let wasDragging = dragging
        let wasMoved = moved
        let start = origin
        let beganAt = startTime
        origin = nil
        dragging = false
        moved = false
        if cancelled {
            if wasDragging, let point = lastNorm { return [.drag(.ended, point)] }
            return []
        }
        if wasDragging {
            let point = normalize(sample.location) ?? lastNorm
            if let point { return [.drag(.ended, point)] }
            return []
        }
        guard let start, !wasMoved else { return [] }
        guard let point = normalize(start) else { return [] }
        if sample.time - beganAt >= longPressDuration {
            lastTapTime = -10
            return [.longPress(point)]
        }
        let isDouble =
            sample.time - lastTapTime <= doubleTapWindow
            && xaHypot(start.x - lastTapPoint.x, start.y - lastTapPoint.y) <= slop * 2
        lastTapTime = sample.time
        lastTapPoint = start
        if isDouble {
            // The first tap already produced a click. This second tap completes the double-click.
            return [.tap(point)]
        }
        return [.tap(point)]
    }
}

public enum InputIntent: Equatable {
    case mouse(phase: XAMousePhase, button: XAMouseButton, x: Double, y: Double, space: XAPointerSpace)
    case scroll(dx: Double, dy: Double, inertia: Bool)
    case key(phase: XAKeyPhase, keyCode: UInt16, modifiers: XAModifierMask, text: String)
    case modifier(XAModifierMask, down: Bool)
    case release
}

public enum GestureMapper {
    public static func intents(for gesture: FingerGesture) -> [InputIntent] {
        switch gesture {
        case .tap(let point):
            return click(.left, at: point)
        case .doubleTap(let point):
            return click(.left, at: point) + click(.left, at: point)
        case .longPress(let point), .twoFingerTap(let point), .twoFingerLongPress(let point):
            return click(.right, at: point)
        case .drag(let phase, let point):
            let mousePhase: XAMousePhase
            switch phase {
            case .began: mousePhase = .down
            case .moved: mousePhase = .move
            case .ended: mousePhase = .up
            }
            return [.mouse(phase: mousePhase, button: .left, x: point.x, y: point.y, space: .absoluteNormalized)]
        case .scroll(let dx, let dy, let inertia):
            return [.scroll(dx: dx, dy: dy, inertia: inertia)]
        case .relativeMove(let dx, let dy):
            return [.mouse(phase: .move, button: .left, x: dx, y: dy, space: .relativeNormalized)]
        case .relativeClick(let button):
            return [
                .mouse(phase: .down, button: button, x: 0, y: 0, space: .relativeNormalized),
                .mouse(phase: .up, button: button, x: 0, y: 0, space: .relativeNormalized)
            ]
        }
    }

    private static func click(_ button: XAMouseButton, at point: XAPoint) -> [InputIntent] {
        [
            .mouse(phase: .down, button: button, x: point.x, y: point.y, space: .absoluteNormalized),
            .mouse(phase: .up, button: button, x: point.x, y: point.y, space: .absoluteNormalized)
        ]
    }
}

public struct TrackpadAcceleration {
    public static func apply(dx: Double, dy: Double, precision: Bool) -> XAPoint {
        let gain = precision ? 0.35 : 1.15
        let speed = min(800, xaHypot(dx, dy))
        let scale = gain * (1 + speed / 500)
        return XAPoint(x: dx * scale, y: dy * scale)
    }
}

public struct TrackpadCursor: Equatable {
    public var normalized: XAPoint
    public init(normalized: XAPoint = XAPoint(x: 0.5, y: 0.5)) {
        self.normalized = normalized
    }
    public mutating func apply(normalizedDelta: XAPoint) -> XAPoint {
        normalized.x = min(1, max(0, normalized.x + normalizedDelta.x))
        normalized.y = min(1, max(0, normalized.y + normalizedDelta.y))
        return normalized
    }
}

public struct KeyShortcut: Equatable {
    public var input: String
    public var modifiers: XAModifierMask
    public init(input: String, modifiers: XAModifierMask) {
        self.input = input
        self.modifiers = modifiers
    }

    public func intents() -> [InputIntent] {
        guard let code = Self.keyCode(for: input) else { return [] }
        return [
            .key(phase: .down, keyCode: code, modifiers: modifiers, text: ""),
            .key(phase: .up, keyCode: code, modifiers: modifiers, text: "")
        ]
    }

    public static func keyCode(for input: String) -> UInt16? {
        switch input {
        case "\u{1b}": return MacKeyCode.escape
        case "UIKeyInputUpArrow": return MacKeyCode.upArrow
        case "UIKeyInputDownArrow": return MacKeyCode.downArrow
        case "UIKeyInputLeftArrow": return MacKeyCode.leftArrow
        case "UIKeyInputRightArrow": return MacKeyCode.rightArrow
        case "\t": return MacKeyCode.tab
        case "\r", "\n": return MacKeyCode.return
        case "=": return 24
        case "-": return 27
        case "UIKeyInputF4": return 118
        default:
            guard input.count == 1, let character = input.first else { return nil }
            return MacKeyCode.letter(character) ?? MacKeyCode.digit(character)
        }
    }
}

public enum TextEntry {
    public static func insert(_ text: String) -> [InputIntent] {
        text.map { character in
            let code = MacKeyCode.letter(character) ?? MacKeyCode.digit(character) ?? 0
            return .key(phase: .typed, keyCode: code, modifiers: [], text: String(character))
        }
    }
    public static func delete() -> [InputIntent] {
        [
            .key(phase: .down, keyCode: MacKeyCode.delete, modifiers: [], text: ""),
            .key(phase: .up, keyCode: MacKeyCode.delete, modifiers: [], text: "")
        ]
    }
}
