import Foundation

public enum XAMousePhase: UInt8, Equatable {
    case move = 0
    case down = 1
    case up = 2
}

public enum XAMouseButton: UInt8, Equatable, Hashable, CaseIterable {
    case left = 0
    case right = 1
    case middle = 2
}

public enum XAPointerSpace: UInt8, Equatable {
    case absoluteNormalized = 0
    case relativeNormalized = 1
}

public enum XAKeyPhase: UInt8, Equatable {
    case down = 0
    case up = 1
    case typed = 2
}

public struct XAHello: Equatable {
    public static let flagRequiresPairing: UInt8 = 1
    public var protocolVersion: UInt16
    public var token: String
    public var deviceName: String
    public var deviceID: String
    /// Bit 0 set means the sender wants pairing enforced even if the host toggle is off.
    public var flags: UInt8
    public init(protocolVersion: UInt16, token: String, deviceName: String, deviceID: String, flags: UInt8 = XAHello.flagRequiresPairing) {
        self.protocolVersion = protocolVersion
        self.token = token
        self.deviceName = deviceName
        self.deviceID = deviceID
        self.flags = flags
    }
}

public struct XAHelloAck: Equatable {
    public var accepted: Bool
    public var session: UInt32
    public var reason: String
    public init(accepted: Bool, session: UInt32, reason: String) {
        self.accepted = accepted
        self.session = session
        self.reason = reason
    }
}

public struct XAMouse: Equatable {
    public var session: UInt32
    public var seq: UInt32
    public var phase: XAMousePhase
    public var button: XAMouseButton
    public var x: Double
    public var y: Double
    public var space: XAPointerSpace
    public init(session: UInt32, seq: UInt32, phase: XAMousePhase, button: XAMouseButton, x: Double, y: Double, space: XAPointerSpace) {
        self.session = session
        self.seq = seq
        self.phase = phase
        self.button = button
        self.x = x
        self.y = y
        self.space = space
    }
}

public struct XAScroll: Equatable {
    public var session: UInt32
    public var seq: UInt32
    public var dxPixels: Double
    public var dyPixels: Double
    public var inertia: Bool
    public init(session: UInt32, seq: UInt32, dxPixels: Double, dyPixels: Double, inertia: Bool) {
        self.session = session
        self.seq = seq
        self.dxPixels = dxPixels
        self.dyPixels = dyPixels
        self.inertia = inertia
    }
}

public struct XAKey: Equatable {
    public var session: UInt32
    public var seq: UInt32
    public var phase: XAKeyPhase
    public var keyCode: UInt16
    public var modifiers: XAModifierMask
    public var text: String
    public init(session: UInt32, seq: UInt32, phase: XAKeyPhase, keyCode: UInt16, modifiers: XAModifierMask, text: String) {
        self.session = session
        self.seq = seq
        self.phase = phase
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.text = text
    }
}

public struct XAModifier: Equatable {
    public var session: UInt32
    public var seq: UInt32
    public var mask: XAModifierMask
    public var down: Bool
    public init(session: UInt32, seq: UInt32, mask: XAModifierMask, down: Bool) {
        self.session = session
        self.seq = seq
        self.mask = mask
        self.down = down
    }
}

public struct XAPing: Equatable {
    public var session: UInt32
    public var clientUnixMs: UInt64
    public init(session: UInt32, clientUnixMs: UInt64) {
        self.session = session
        self.clientUnixMs = clientUnixMs
    }
}

public struct XAPong: Equatable {
    public var session: UInt32
    public var clientUnixMs: UInt64
    public var hostUnixMs: UInt64
    public init(session: UInt32, clientUnixMs: UInt64, hostUnixMs: UInt64) {
        self.session = session
        self.clientUnixMs = clientUnixMs
        self.hostUnixMs = hostUnixMs
    }
}

public enum WindowAction: UInt8, Equatable, Codable {
    case fill = 1
    case snapLeft = 2
    case snapRight = 3
    case snapFull = 4
    case moveToMain = 5
    case moveToVirtual = 6
    case moveAcross = 7
    case saveLayout = 8
    case restoreLayout = 9
    case tileTopLeft = 10
    case tileTopRight = 11
    case tileBottomLeft = 12
    case tileBottomRight = 13
    case fillToggle = 14
    case pressClose = 15
    case pressMinimize = 16
    case pressZoom = 17
    case notificationCenter = 18
    case missionControl = 19
    case appExpose = 20
    case launchpad = 21
    case controlCenter = 22
}

public enum ClipboardKind: UInt8, Equatable {
    case text = 1
    case imagePNG = 2
}

public struct XAClipboard: Equatable {
    public static let maxTextBytes = 12_000
    public static let maxImageBytes = 200_000
    public static var maxBytes: Int { maxTextBytes }
    public var session: UInt32
    public var seq: UInt32
    public var revision: UInt64
    public var kind: ClipboardKind
    public var text: String
    public var image: Data
    public init(session: UInt32, seq: UInt32, revision: UInt64, text: String, kind: ClipboardKind = .text, image: Data = Data()) {
        self.session = session
        self.seq = seq
        self.revision = revision
        self.kind = kind
        self.text = text
        self.image = image
    }
}

public struct XAWindowCommand: Equatable {
    public var session: UInt32
    public var seq: UInt32
    public var action: WindowAction
    public init(session: UInt32, seq: UInt32, action: WindowAction) {
        self.session = session
        self.seq = seq
        self.action = action
    }
}

public enum XAAudioCodec: UInt8, Equatable {
    case pcm = 0
    case aac = 1
}

public struct XAAudio: Equatable {
    public static let maxBytes = 8_192
    /// AAC-LC uses 1024-sample packets. At 48 kHz that is about 21 ms, plus the network hop.
    public static let aacPacketMilliseconds = 21
    public var session: UInt32
    public var sampleRate: UInt32
    public var channels: UInt16
    public var codec: XAAudioCodec
    public var hostTimeMs: Double
    public var payload: Data
    public var pcm: Data { payload }
    public init(session: UInt32, sampleRate: UInt32, channels: UInt16, pcm: Data, codec: XAAudioCodec = .pcm, hostTimeMs: Double = 0) {
        self.session = session
        self.sampleRate = sampleRate
        self.channels = channels
        self.codec = codec
        self.hostTimeMs = hostTimeMs
        self.payload = pcm
    }
}

public enum ChromeOp: UInt8, Equatable {
    case resize = 1
    case menu = 2
}

public struct XAChromeCommand: Equatable {
    public var session: UInt32
    public var seq: UInt32
    public var op: ChromeOp
    public var index: UInt16
    public var windowIndex: UInt16
    public var dx: Double
    public var dy: Double
    public init(session: UInt32, seq: UInt32, op: ChromeOp, index: UInt16, windowIndex: UInt16, dx: Double, dy: Double) {
        self.session = session
        self.seq = seq
        self.op = op
        self.index = index
        self.windowIndex = windowIndex
        self.dx = dx
        self.dy = dy
    }
}

public struct XAPresetCommand: Equatable {
    public var session: UInt32
    public var seq: UInt32
    public var name: String
    public init(session: UInt32, seq: UInt32, name: String) {
        self.session = session
        self.seq = seq
        self.name = name
    }
}

public struct XARelease: Equatable {
    public var session: UInt32
    public var seq: UInt32
    public init(session: UInt32, seq: UInt32) {
        self.session = session
        self.seq = seq
    }
}
