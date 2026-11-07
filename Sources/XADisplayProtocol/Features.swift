import Foundation

public struct GestureTuning: Equatable, Codable {
    public var slop: Double
    public var doubleTapWindow: Double
    public var longPressDuration: Double
    public var scrollGain: Double
    public var sidebarOnLeft: Bool

    public init(slop: Double = 12, doubleTapWindow: Double = 0.35, longPressDuration: Double = 0.45, scrollGain: Double = 1, sidebarOnLeft: Bool = true) {
        self.slop = slop
        self.doubleTapWindow = doubleTapWindow
        self.longPressDuration = longPressDuration
        self.scrollGain = scrollGain
        self.sidebarOnLeft = sidebarOnLeft
    }

    public func clamped() -> GestureTuning {
        GestureTuning(
            slop: min(40, max(4, slop)),
            doubleTapWindow: min(0.8, max(0.15, doubleTapWindow)),
            longPressDuration: min(1.2, max(0.25, longPressDuration)),
            scrollGain: min(3, max(0.25, scrollGain)),
            sidebarOnLeft: sidebarOnLeft
        )
    }
}

/// Every extra is off or on independently. Pairing defaults on; clipboard and audio default off.
public struct XAFeatureSettings: Equatable, Codable {
    public var requirePairing: Bool
    public var clipboardSync: Bool
    public var threeFingerShortcuts: Bool
    public var pinchMagnifier: Bool
    public var commandStrip: Bool
    public var windowSnapping: Bool
    public var audio: Bool
    public var savedPresets: Bool
    public var gestureTuning: GestureTuning
    public var autoConnectUSB: Bool
    public var touchscreenGestures: Bool
    public var wifiFallback: Bool
    public var trackpadMode: Bool
    public var scrollInertia: Bool
    public var showStats: Bool
    public var precisionMode: Bool
    public var inputRotation: Int

    public init(
        requirePairing: Bool = true,
        clipboardSync: Bool = false,
        threeFingerShortcuts: Bool = true,
        pinchMagnifier: Bool = true,
        commandStrip: Bool = true,
        windowSnapping: Bool = true,
        audio: Bool = false,
        savedPresets: Bool = true,
        gestureTuning: GestureTuning = GestureTuning(),
        autoConnectUSB: Bool = true,
        touchscreenGestures: Bool = true,
        wifiFallback: Bool = true,
        trackpadMode: Bool = false,
        scrollInertia: Bool = true,
        showStats: Bool = true,
        precisionMode: Bool = false,
        inputRotation: Int = 0
    ) {
        self.requirePairing = requirePairing
        self.clipboardSync = clipboardSync
        self.threeFingerShortcuts = threeFingerShortcuts
        self.pinchMagnifier = pinchMagnifier
        self.commandStrip = commandStrip
        self.windowSnapping = windowSnapping
        self.audio = audio
        self.savedPresets = savedPresets
        self.gestureTuning = gestureTuning
        self.autoConnectUSB = autoConnectUSB
        self.touchscreenGestures = touchscreenGestures
        self.wifiFallback = wifiFallback
        self.trackpadMode = trackpadMode
        self.scrollInertia = scrollInertia
        self.showStats = showStats
        self.precisionMode = precisionMode
        self.inputRotation = inputRotation
    }
}

public struct Magnifier: Equatable {
    public var scale: Double
    public var center: XAPoint
    public init(scale: Double = 1, center: XAPoint = XAPoint(x: 0.5, y: 0.5)) {
        self.scale = scale
        self.center = center
    }

    public mutating func pinch(by factor: Double, around normalizedCenter: XAPoint) {
        guard factor.isFinite, factor > 0 else { return }
        scale = min(4, max(1, scale * factor))
        if scale <= 1.001 {
            scale = 1
            center = XAPoint(x: 0.5, y: 0.5)
        } else {
            center = XAPoint(x: min(1, max(0, normalizedCenter.x)), y: min(1, max(0, normalizedCenter.y)))
        }
    }

    public var visibleRect: XARect {
        let width = 1 / scale
        let height = 1 / scale
        let x = min(max(center.x - width / 2, 0), 1 - width)
        let y = min(max(center.y - height / 2, 0), 1 - height)
        return XARect(x: x, y: y, width: width, height: height)
    }

    /// Maps a point in the on-screen video (0...1 of what is visible) back to the full frame.
    public func videoNormalized(viewNormalized: XAPoint) -> XAPoint {
        let visible = visibleRect
        return XAPoint(
            x: visible.origin.x + min(1, max(0, viewNormalized.x)) * visible.width,
            y: visible.origin.y + min(1, max(0, viewNormalized.y)) * visible.height
        )
    }
}

public enum ThreeFingerAction: Equatable {
    case undo, redo, copy, paste
}

public enum ThreeFingerMapper {
    public static func action(dx: Double, dy: Double, minimum: Double = 24) -> ThreeFingerAction? {
        if abs(dx) < minimum && abs(dy) < minimum { return nil }
        if abs(dx) >= abs(dy) {
            return dx < 0 ? .undo : .redo
        }
        return dy < 0 ? .copy : .paste
    }

    public static func intents(for action: ThreeFingerAction) -> [InputIntent] {
        switch action {
        case .undo:
            return KeyShortcut(input: "z", modifiers: .command).intents()
        case .redo:
            return KeyShortcut(input: "z", modifiers: [.command, .shift]).intents()
        case .copy:
            return KeyShortcut(input: "c", modifiers: .command).intents()
        case .paste:
            return KeyShortcut(input: "v", modifiers: .command).intents()
        }
    }
}

public struct CommandStripItem: Equatable, Codable {
    public var id: String
    public var title: String
    public var input: String
    public var modifiers: UInt8
    public init(id: String, title: String, input: String, modifiers: UInt8) {
        self.id = id
        self.title = title
        self.input = input
        self.modifiers = modifiers
    }

    public static let standard: [CommandStripItem] = [
        CommandStripItem(id: "esc", title: "Esc", input: "\u{1b}", modifiers: 0),
        CommandStripItem(id: "undo", title: "Undo", input: "z", modifiers: XAModifierMask.command.rawValue),
        CommandStripItem(id: "redo", title: "Redo", input: "z", modifiers: XAModifierMask.command.rawValue | XAModifierMask.shift.rawValue),
        CommandStripItem(id: "copy", title: "Copy", input: "c", modifiers: XAModifierMask.command.rawValue),
        CommandStripItem(id: "paste", title: "Paste", input: "v", modifiers: XAModifierMask.command.rawValue),
        CommandStripItem(id: "snap-left", title: "Left", input: "", modifiers: 0),
        CommandStripItem(id: "snap-right", title: "Right", input: "", modifiers: 0),
        CommandStripItem(id: "fill", title: "Fill", input: "", modifiers: 0),
    ]

    public func shortcutIntents() -> [InputIntent] {
        guard !input.isEmpty else { return [] }
        return KeyShortcut(input: input, modifiers: XAModifierMask(rawValue: modifiers)).intents()
    }

    public var windowAction: WindowAction? {
        switch id {
        case "snap-left": return .snapLeft
        case "snap-right": return .snapRight
        case "fill": return .fill
        default: return nil
        }
    }
}

public enum SnapZone: Equatable {
    case leftHalf, rightHalf, full, mainDisplay
}

public enum WindowSnap {
    public static func frame(zone: SnapZone, virtualDisplay: XARect, mainDisplay: XARect) -> XARect {
        switch zone {
        case .leftHalf:
            return XARect(x: virtualDisplay.minX, y: virtualDisplay.minY, width: virtualDisplay.width / 2, height: virtualDisplay.height)
        case .rightHalf:
            return XARect(x: virtualDisplay.minX + virtualDisplay.width / 2, y: virtualDisplay.minY, width: virtualDisplay.width / 2, height: virtualDisplay.height)
        case .full:
            return virtualDisplay
        case .mainDisplay:
            return XARect(x: mainDisplay.minX + 40, y: mainDisplay.minY + 40, width: min(900, mainDisplay.width - 80), height: min(600, mainDisplay.height - 80))
        }
    }

    public static func flick(dx: Double, dy: Double, speed: Double, minimumSpeed: Double = 900) -> SnapZone? {
        guard speed >= minimumSpeed, abs(dx) > abs(dy), abs(dx) > 40 else { return nil }
        return dx < 0 ? .leftHalf : .rightHalf
    }
}

public enum TouchscreenGesture: Equatable {
    case fillWindow
    case snap(SnapZone)
    case openDrawer
    case precisionOverlay
}

public enum TouchGestureRouter {
    public static func titleBarFill(enabled: Bool, normalizedY: Double, tapCount: Int, topBand: Double = 0.08) -> Bool {
        enabled && tapCount >= 2 && normalizedY >= 0 && normalizedY <= topBand
    }

    public static func edgeDrawer(enabled: Bool, startX: Double, viewWidth: Double, translationX: Double, sidebarOnLeft: Bool) -> Bool {
        guard enabled, viewWidth > 0, abs(translationX) > 24 else { return false }
        if sidebarOnLeft {
            return startX < 28 && translationX > 0
        }
        return startX > viewWidth - 28 && translationX < 0
    }
}

public struct SavedDisplayPreset: Equatable, Codable {
    public var name: String
    public var preset: StreamPreset.ID
    public var portrait: Bool
    public init(name: String, preset: StreamPreset.ID, portrait: Bool) {
        self.name = name
        self.preset = preset
        self.portrait = portrait
    }
}

public struct PresetLibrary {
    public var enabled: Bool
    public private(set) var items: [SavedDisplayPreset]
    public init(enabled: Bool = true, items: [SavedDisplayPreset] = []) {
        self.enabled = enabled
        self.items = items
    }
    public mutating func save(_ item: SavedDisplayPreset) {
        guard enabled else { return }
        items.removeAll { $0.name == item.name }
        items.append(item)
    }
    public func named(_ name: String) -> SavedDisplayPreset? {
        guard enabled else { return nil }
        return items.first { $0.name == name }
    }
}

public enum AudioPolicy {
    public static func accept(enabled: Bool, armed: Bool, byteCount: Int, channels: Int, codec: XAAudioCodec = .pcm) -> Bool {
        guard enabled, armed, channels >= 1, channels <= 2, byteCount > 0, byteCount <= XAAudio.maxBytes else { return false }
        if codec == .pcm {
            return byteCount % (2 * channels) == 0
        }
        return true
    }
}

public enum ClipboardPolicy {
    public static func accept(enabled: Bool, armed: Bool, utf8Count: Int) -> Bool {
        enabled && armed && utf8Count <= XAClipboard.maxBytes
    }
}
