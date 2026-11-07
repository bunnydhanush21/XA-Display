import Foundation

public enum SettingValue: Equatable {
    case bool(Bool)
    case number(Double)
    case choice(String)
}

public struct SettingsRow: Equatable {
    public var id: String
    public var title: String
    public var section: String
    public var kind: String
    public var choices: [String]
    public var minimum: Double
    public var maximum: Double
    public var onPad: Bool
    public var onHost: Bool

    public init(id: String, title: String, section: String, kind: String, choices: [String] = [], minimum: Double = 0, maximum: Double = 1, onPad: Bool = true, onHost: Bool = false) {
        self.id = id
        self.title = title
        self.section = section
        self.kind = kind
        self.choices = choices
        self.minimum = minimum
        self.maximum = maximum
        self.onPad = onPad
        self.onHost = onHost
    }
}

public enum SettingsCatalog {
    public static let padSections = [
        "Connection", "Display", "Touch", "Sidebar", "Keyboard", "Clipboard", "Audio",
        "Touch Bar", "Window actions", "Media remote", "Metrics", "Battery care", "Security", "About"
    ]
    public static let hostSections = ["General", "Display", "Input", "Audio", "Clipboard", "Security", "Permissions"]

    public static let rows: [SettingsRow] = [
        SettingsRow(id: "connection.usb", title: "USB first", section: "Connection", kind: "toggle", onHost: true),
        SettingsRow(id: "connection.wifi", title: "Wi-Fi fallback", section: "Connection", kind: "toggle", onHost: true),
        SettingsRow(id: "connection.oneTap", title: "Auto-connect last Mac", section: "Connection", kind: "toggle", onHost: true),
        SettingsRow(id: "connection.remember", title: "Remember Macs", section: "Connection", kind: "toggle", onHost: true),
        SettingsRow(id: "connection.lowLatency", title: "Low Latency Wi-Fi", section: "Connection", kind: "toggle", onHost: true),
        SettingsRow(id: "display.preset", title: "Preset", section: "Display", kind: "choice", choices: ["balanced", "safe", "native"], onHost: true),
        SettingsRow(id: "display.detail", title: "Resolution, FPS, bitrate", section: "Display", kind: "info", onHost: true),
        SettingsRow(id: "touch.mode", title: "Pointer mode", section: "Touch", kind: "choice", choices: ["direct", "trackpad"]),
        SettingsRow(id: "touch.scroll", title: "Two-finger scroll", section: "Touch", kind: "toggle"),
        SettingsRow(id: "touch.momentum", title: "Momentum", section: "Touch", kind: "toggle"),
        SettingsRow(id: "touch.rightClick", title: "Right-click", section: "Touch", kind: "choice", choices: ["longPress", "twoFinger", "both"]),
        SettingsRow(id: "touch.three", title: "Three-finger gestures", section: "Touch", kind: "toggle"),
        SettingsRow(id: "touch.pinch", title: "Pinch magnifier", section: "Touch", kind: "toggle"),
        SettingsRow(id: "touch.edge", title: "Edge drawer", section: "Touch", kind: "toggle"),
        SettingsRow(id: "touch.hold", title: "Hold duration", section: "Touch", kind: "slider", minimum: 0.25, maximum: 1.2),
        SettingsRow(id: "touch.threshold", title: "Movement threshold", section: "Touch", kind: "slider", minimum: 4, maximum: 40),
        SettingsRow(id: "sidebar.show", title: "Show sidebar", section: "Sidebar", kind: "toggle"),
        SettingsRow(id: "sidebar.left", title: "Left-handed", section: "Sidebar", kind: "toggle"),
        SettingsRow(id: "sidebar.large", title: "Large buttons", section: "Sidebar", kind: "toggle"),
        SettingsRow(id: "keyboard.enabled", title: "Software keyboard", section: "Keyboard", kind: "toggle"),
        SettingsRow(id: "clipboard.sync", title: "Clipboard sync", section: "Clipboard", kind: "toggle", onHost: true),
        SettingsRow(id: "audio.on", title: "Audio", section: "Audio", kind: "toggle", onHost: true),
        SettingsRow(id: "audio.mode", title: "Audio mode", section: "Audio", kind: "choice", choices: ["all", "selected", "displayApps"], onHost: true),
        SettingsRow(id: "audio.volume", title: "Volume", section: "Audio", kind: "slider", minimum: 0, maximum: 1, onHost: true),
        SettingsRow(id: "strip.command", title: "Touch Bar strip", section: "Touch Bar", kind: "toggle"),
        SettingsRow(id: "window.snap", title: "Window actions", section: "Window actions", kind: "toggle", onHost: true),
        SettingsRow(id: "window.gestures", title: "Touch-style window gestures", section: "Window actions", kind: "toggle", onHost: true),
        SettingsRow(id: "media.remote", title: "Media remote", section: "Media remote", kind: "toggle", onHost: true),
        SettingsRow(id: "metrics.show", title: "Metrics overlay", section: "Metrics", kind: "toggle"),
        SettingsRow(id: "battery.telemetry", title: "Telemetry", section: "Battery care", kind: "toggle"),
        SettingsRow(id: "battery.limit", title: "Charge limit (experimental)", section: "Battery care", kind: "toggle"),
        SettingsRow(id: "battery.stop", title: "Stop charging at", section: "Battery care", kind: "slider", minimum: 60, maximum: 100),
        SettingsRow(id: "battery.resume", title: "Resume charging at", section: "Battery care", kind: "slider", minimum: 21, maximum: 95),
        SettingsRow(id: "battery.restore", title: "Restore normal charging", section: "Battery care", kind: "action"),
        SettingsRow(id: "battery.disable", title: "Disable battery care", section: "Battery care", kind: "action"),
        SettingsRow(id: "security.pairing", title: "Require pairing", section: "Security", kind: "toggle", onHost: true),
        SettingsRow(id: "security.devices", title: "Paired devices", section: "Security", kind: "info", onHost: true),
        SettingsRow(id: "security.revoke", title: "Revoke pairing", section: "Security", kind: "action", onHost: true),
        SettingsRow(id: "about.diagnostics", title: "Export diagnostics", section: "About", kind: "action"),
        SettingsRow(id: "about.reset", title: "Reset to defaults", section: "About", kind: "action"),
        SettingsRow(id: "permissions.screen", title: "Screen Recording", section: "Permissions", kind: "action", onPad: false, onHost: true),
        SettingsRow(id: "permissions.access", title: "Accessibility", section: "Permissions", kind: "action", onPad: false, onHost: true)
    ]

    public static func sections(host: Bool) -> [String] { host ? hostSections : padSections }

    public static func rows(in section: String, host: Bool) -> [SettingsRow] {
        rows.filter { $0.section == section && (host ? $0.onHost : $0.onPad) }
    }
}

public struct XASettingsDocument: Equatable, Codable {
    public static let currentVersion = 1
    public var version: Int
    public var features: XAFeatureSettings
    public var assist: TouchAssist
    public var charge: ChargeLimitConfig
    public var audioVolume: Double
    public var audioMode: String
    public var preset: String
    public var sidebarVisible: Bool
    public var twoFingerScroll: Bool
    public var rightClick: String
    public var keyboardEnabled: Bool
    public var pairedIDs: [String]

    public init(
        version: Int = XASettingsDocument.currentVersion,
        features: XAFeatureSettings = XAFeatureSettings(),
        assist: TouchAssist = TouchAssist(),
        charge: ChargeLimitConfig = ChargeLimitConfig(),
        audioVolume: Double = 1,
        audioMode: String = AudioRouteMode.all.rawValue,
        preset: String = StreamPreset.ID.balanced.rawValue,
        sidebarVisible: Bool = true,
        twoFingerScroll: Bool = true,
        rightClick: String = "both",
        keyboardEnabled: Bool = true,
        pairedIDs: [String] = []
    ) {
        self.version = version
        self.features = features
        self.assist = assist
        self.charge = charge
        self.audioVolume = audioVolume
        self.audioMode = audioMode
        self.preset = preset
        self.sidebarVisible = sidebarVisible
        self.twoFingerScroll = twoFingerScroll
        self.rightClick = rightClick
        self.keyboardEnabled = keyboardEnabled
        self.pairedIDs = pairedIDs
    }

    public static var defaults: XASettingsDocument { XASettingsDocument() }

    public static func migrate(featuresJSON: Data) -> XASettingsDocument {
        let features = (try? JSONDecoder().decode(XAFeatureSettings.self, from: featuresJSON)) ?? XAFeatureSettings()
        return XASettingsDocument(features: features)
    }

    public static func decode(_ data: Data) -> XASettingsDocument {
        if let document = try? JSONDecoder().decode(XASettingsDocument.self, from: data), document.version >= 1 {
            return document.normalized()
        }
        return migrate(featuresJSON: data).normalized()
    }

    public func encode() -> Data {
        (try? JSONEncoder().encode(normalized())) ?? Data()
    }

    public func normalized() -> XASettingsDocument {
        var copy = self
        copy.version = XASettingsDocument.currentVersion
        copy.features.gestureTuning = copy.features.gestureTuning.clamped()
        copy.charge = copy.charge.validated()
        copy.audioVolume = min(1, max(0, copy.audioVolume))
        if StreamPreset.ID(rawValue: copy.preset) == nil { copy.preset = StreamPreset.ID.balanced.rawValue }
        if AudioRouteMode(rawValue: copy.audioMode) == nil { copy.audioMode = AudioRouteMode.all.rawValue }
        if !["longPress", "twoFinger", "both"].contains(copy.rightClick) { copy.rightClick = "both" }
        return copy
    }

    public func value(for id: String) -> SettingValue {
        switch id {
        case "connection.usb": return .bool(features.autoConnectUSB)
        case "connection.wifi": return .bool(features.wifiFallback)
        case "connection.oneTap": return .bool(features.oneTapReconnect)
        case "connection.remember": return .bool(features.rememberMacs)
        case "connection.lowLatency": return .bool(features.lowLatencyWiFi)
        case "display.preset": return .choice(preset)
        case "display.detail":
            let spec = StreamPreset.preset(StreamPreset.ID(rawValue: preset) ?? .balanced)
            return .choice("\(spec.width)×\(spec.height) · \(spec.fps) fps · \(spec.bitrateUSB / 1_000_000) Mb/s USB")
        case "touch.mode": return .choice(features.trackpadMode ? "trackpad" : "direct")
        case "touch.scroll": return .bool(twoFingerScroll)
        case "touch.momentum": return .bool(features.scrollInertia)
        case "touch.rightClick": return .choice(rightClick)
        case "touch.three": return .bool(features.threeFingerShortcuts)
        case "touch.pinch": return .bool(features.pinchMagnifier)
        case "touch.edge": return .bool(assist.edgeDrawer)
        case "touch.hold": return .number(features.gestureTuning.longPressDuration)
        case "touch.threshold": return .number(features.gestureTuning.slop)
        case "sidebar.show": return .bool(sidebarVisible)
        case "sidebar.left": return .bool(features.gestureTuning.sidebarOnLeft)
        case "sidebar.large": return .bool(assist.largeButtons)
        case "keyboard.enabled": return .bool(keyboardEnabled)
        case "clipboard.sync": return .bool(features.clipboardSync)
        case "audio.on": return .bool(features.audio)
        case "audio.mode": return .choice(audioMode)
        case "audio.volume": return .number(audioVolume)
        case "strip.command": return .bool(features.commandStrip)
        case "window.snap": return .bool(features.windowSnapping)
        case "window.gestures": return .bool(features.touchscreenGestures)
        case "media.remote": return .bool(features.mediaRemote)
        case "metrics.show": return .bool(features.showStats)
        case "battery.telemetry": return .bool(features.batteryTelemetry)
        case "battery.limit": return .bool(features.chargeLimit)
        case "battery.stop": return .number(charge.stopAtPercent)
        case "battery.resume": return .number(charge.resumeAtPercent)
        case "security.pairing": return .bool(features.requirePairing)
        case "security.devices": return .choice(pairedIDs.isEmpty ? "None saved" : pairedIDs.joined(separator: ", "))
        default: return .choice("")
        }
    }

    public mutating func set(_ value: SettingValue, for id: String) {
        switch id {
        case "connection.usb": if case .bool(let on) = value { features.autoConnectUSB = on }
        case "connection.wifi": if case .bool(let on) = value { features.wifiFallback = on }
        case "connection.oneTap": if case .bool(let on) = value { features.oneTapReconnect = on }
        case "connection.remember": if case .bool(let on) = value { features.rememberMacs = on }
        case "connection.lowLatency": if case .bool(let on) = value { features.lowLatencyWiFi = on }
        case "display.preset": if case .choice(let choice) = value { preset = choice }
        case "touch.mode": if case .choice(let choice) = value { features.trackpadMode = choice == "trackpad" }
        case "touch.scroll": if case .bool(let on) = value { twoFingerScroll = on }
        case "touch.momentum": if case .bool(let on) = value { features.scrollInertia = on }
        case "touch.rightClick": if case .choice(let choice) = value { rightClick = choice }
        case "touch.three": if case .bool(let on) = value { features.threeFingerShortcuts = on }
        case "touch.pinch": if case .bool(let on) = value { features.pinchMagnifier = on }
        case "touch.edge": if case .bool(let on) = value { assist.edgeDrawer = on }
        case "touch.hold": if case .number(let number) = value { features.gestureTuning.longPressDuration = number }
        case "touch.threshold": if case .number(let number) = value { features.gestureTuning.slop = number }
        case "sidebar.show": if case .bool(let on) = value { sidebarVisible = on }
        case "sidebar.left": if case .bool(let on) = value { features.gestureTuning.sidebarOnLeft = on }
        case "sidebar.large": if case .bool(let on) = value { assist.largeButtons = on }
        case "keyboard.enabled": if case .bool(let on) = value { keyboardEnabled = on }
        case "clipboard.sync": if case .bool(let on) = value { features.clipboardSync = on }
        case "audio.on": if case .bool(let on) = value { features.audio = on }
        case "audio.mode": if case .choice(let choice) = value { audioMode = choice }
        case "audio.volume": if case .number(let number) = value { audioVolume = number }
        case "strip.command": if case .bool(let on) = value { features.commandStrip = on }
        case "window.snap": if case .bool(let on) = value { features.windowSnapping = on }
        case "window.gestures": if case .bool(let on) = value { features.touchscreenGestures = on }
        case "media.remote": if case .bool(let on) = value { features.mediaRemote = on }
        case "metrics.show": if case .bool(let on) = value { features.showStats = on }
        case "battery.telemetry": if case .bool(let on) = value { features.batteryTelemetry = on }
        case "battery.limit": if case .bool(let on) = value { features.chargeLimit = on }
        case "battery.stop": if case .number(let number) = value { charge.stopAtPercent = number }
        case "battery.resume": if case .number(let number) = value { charge.resumeAtPercent = number }
        case "security.pairing": if case .bool(let on) = value { features.requirePairing = on }
        default: break
        }
        self = normalized()
    }

    public mutating func reset() { self = XASettingsDocument.defaults }
}

public enum SettingsSync {
    public static func encode(_ document: XASettingsDocument) -> String {
        let object: [String: Any] = [
            "clipboardSync": document.features.clipboardSync,
            "audio": document.features.audio,
            "wifiFallback": document.features.wifiFallback,
            "requirePairing": document.features.requirePairing,
            "mediaRemote": document.features.mediaRemote,
            "windowSnapping": document.features.windowSnapping,
            "autoConnectUSB": document.features.autoConnectUSB,
            "lowLatencyWiFi": document.features.lowLatencyWiFi,
            "preset": document.preset,
            "audioMode": document.audioMode,
            "audioVolume": document.audioVolume
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    public static func apply(_ payload: String, to document: XASettingsDocument) -> XASettingsDocument {
        guard let data = payload.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return document }
        var copy = document
        if let value = object["clipboardSync"] as? Bool { copy.features.clipboardSync = value }
        if let value = object["audio"] as? Bool { copy.features.audio = value }
        if let value = object["wifiFallback"] as? Bool { copy.features.wifiFallback = value }
        if let value = object["requirePairing"] as? Bool { copy.features.requirePairing = value }
        if let value = object["mediaRemote"] as? Bool { copy.features.mediaRemote = value }
        if let value = object["windowSnapping"] as? Bool { copy.features.windowSnapping = value }
        if let value = object["autoConnectUSB"] as? Bool { copy.features.autoConnectUSB = value }
        if let value = object["lowLatencyWiFi"] as? Bool { copy.features.lowLatencyWiFi = value }
        if let value = object["preset"] as? String { copy.preset = value }
        if let value = object["audioMode"] as? String { copy.audioMode = value }
        if let value = object["audioVolume"] as? Double { copy.audioVolume = value }
        return copy.normalized()
    }
}
