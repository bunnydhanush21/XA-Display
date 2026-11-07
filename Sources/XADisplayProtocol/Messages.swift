import Foundation

public enum ProtocolError: Error, Equatable {
    case truncated
    case badVersion
    case lengthMismatch
    case tooLarge
    case stringTooLong
    case badUTF8
    case badEnum
}

public struct ByteWriter {
    public private(set) var data = Data()
    public init() {}
    public mutating func u8(_ value: UInt8) { data.append(value) }
    public mutating func u16(_ value: UInt16) { appendInteger(value.bigEndian) }
    public mutating func u32(_ value: UInt32) { appendInteger(value.bigEndian) }
    public mutating func u64(_ value: UInt64) { appendInteger(value.bigEndian) }
    public mutating func f64(_ value: Double) { u64(value.bitPattern) }
    public mutating func bytes(_ value: Data) { data.append(value) }
    public mutating func str(_ value: String, maxBytes: Int = 2_048) throws {
        let utf = Array(value.utf8)
        guard utf.count <= maxBytes, utf.count <= Int(UInt16.max) else { throw ProtocolError.stringTooLong }
        u16(UInt16(utf.count))
        data.append(contentsOf: utf)
    }
    private mutating func appendInteger<T>(_ value: T) {
        var value = value
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }
}

public struct ByteReader {
    public let data: Data
    public var offset = 0
    public var remaining: Int { data.count - offset }
    public init(data: Data) { self.data = data }

    public mutating func u8() throws -> UInt8 {
        guard remaining >= 1 else { throw ProtocolError.truncated }
        defer { offset += 1 }
        return data[offset]
    }
    public mutating func u16() throws -> UInt16 {
        guard remaining >= 2 else { throw ProtocolError.truncated }
        let value = (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
        offset += 2
        return value
    }
    public mutating func u32() throws -> UInt32 {
        guard remaining >= 4 else { throw ProtocolError.truncated }
        let value = (UInt32(data[offset]) << 24) | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8) | UInt32(data[offset + 3])
        offset += 4
        return value
    }
    public mutating func u64() throws -> UInt64 {
        guard remaining >= 8 else { throw ProtocolError.truncated }
        var value: UInt64 = 0
        for index in 0..<8 {
            value = (value << 8) | UInt64(data[offset + index])
        }
        offset += 8
        return value
    }
    public mutating func f64() throws -> Double { Double(bitPattern: try u64()) }
    public mutating func str(maxBytes: Int = 2_048) throws -> String {
        let count = Int(try u16())
        guard count <= maxBytes else { throw ProtocolError.stringTooLong }
        guard count <= remaining else { throw ProtocolError.truncated }
        let slice = data.subdata(in: offset..<(offset + count))
        offset += count
        guard let string = String(data: slice, encoding: .utf8) else { throw ProtocolError.badUTF8 }
        return string
    }
}

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

public enum XAInputMessage: Equatable {
    case hello(XAHello)
    case helloAck(XAHelloAck)
    case mouse(XAMouse)
    case scroll(XAScroll)
    case key(XAKey)
    case modifier(XAModifier)
    case ping(XAPing)
    case pong(XAPong)
    case release(XARelease)
    case clipboard(XAClipboard)
    case window(XAWindowCommand)
    case audio(XAAudio)
    case preset(XAPresetCommand)
    case chrome(XAChromeCommand)

    public func encode() throws -> Data {
        switch self {
        case .hello(let hello):
            var payload = ByteWriter()
            payload.u16(hello.protocolVersion)
            try payload.str(hello.token)
            try payload.str(hello.deviceName)
            try payload.str(hello.deviceID)
            payload.u8(hello.flags)
            return Self.wrap(type: 1, payload: payload.data)
        case .helloAck(let ack):
            var payload = ByteWriter()
            payload.u8(ack.accepted ? 1 : 0)
            payload.u32(ack.session)
            try payload.str(ack.reason)
            return Self.wrap(type: 2, payload: payload.data)
        case .mouse(let mouse):
            var payload = ByteWriter()
            payload.u32(mouse.session)
            payload.u32(mouse.seq)
            payload.u8(mouse.phase.rawValue)
            payload.u8(mouse.button.rawValue)
            payload.u8(mouse.space.rawValue)
            payload.u8(0)
            payload.f64(mouse.x)
            payload.f64(mouse.y)
            return Self.wrap(type: 3, payload: payload.data)
        case .scroll(let scroll):
            var payload = ByteWriter()
            payload.u32(scroll.session)
            payload.u32(scroll.seq)
            payload.f64(scroll.dxPixels)
            payload.f64(scroll.dyPixels)
            payload.u8(scroll.inertia ? 1 : 0)
            payload.u8(0); payload.u8(0); payload.u8(0)
            return Self.wrap(type: 4, payload: payload.data)
        case .key(let key):
            var payload = ByteWriter()
            payload.u32(key.session)
            payload.u32(key.seq)
            payload.u8(key.phase.rawValue)
            payload.u8(0)
            payload.u16(key.keyCode)
            payload.u32(UInt32(key.modifiers.rawValue))
            try payload.str(key.text)
            return Self.wrap(type: 5, payload: payload.data)
        case .modifier(let modifier):
            var payload = ByteWriter()
            payload.u32(modifier.session)
            payload.u32(modifier.seq)
            payload.u8(modifier.mask.rawValue)
            payload.u8(modifier.down ? 1 : 0)
            return Self.wrap(type: 6, payload: payload.data)
        case .ping(let ping):
            var payload = ByteWriter()
            payload.u32(ping.session)
            payload.u64(ping.clientUnixMs)
            return Self.wrap(type: 7, payload: payload.data)
        case .pong(let pong):
            var payload = ByteWriter()
            payload.u32(pong.session)
            payload.u64(pong.clientUnixMs)
            payload.u64(pong.hostUnixMs)
            return Self.wrap(type: 8, payload: payload.data)
        case .release(let release):
            var payload = ByteWriter()
            payload.u32(release.session)
            payload.u32(release.seq)
            return Self.wrap(type: 9, payload: payload.data)
        case .clipboard(let clip):
            var payload = ByteWriter()
            payload.u32(clip.session)
            payload.u32(clip.seq)
            payload.u64(clip.revision)
            payload.u8(clip.kind.rawValue)
            switch clip.kind {
            case .text:
                try payload.str(clip.text, maxBytes: XAClipboard.maxTextBytes)
            case .imagePNG:
                guard clip.image.count <= XAClipboard.maxImageBytes else { throw ProtocolError.tooLarge }
                payload.u32(UInt32(clip.image.count))
                payload.bytes(clip.image)
            }
            return Self.wrap(type: 10, payload: payload.data)
        case .window(let command):
            var payload = ByteWriter()
            payload.u32(command.session)
            payload.u32(command.seq)
            payload.u8(command.action.rawValue)
            return Self.wrap(type: 11, payload: payload.data)
        case .audio(let audio):
            guard audio.payload.count <= XAAudio.maxBytes else { throw ProtocolError.tooLarge }
            var payload = ByteWriter()
            payload.u32(audio.session)
            payload.u32(audio.sampleRate)
            payload.u16(audio.channels)
            payload.u16(UInt16(audio.codec.rawValue))
            payload.f64(audio.hostTimeMs)
            payload.u32(UInt32(audio.payload.count))
            payload.bytes(audio.payload)
            return Self.wrap(type: 12, payload: payload.data)
        case .preset(let preset):
            var payload = ByteWriter()
            payload.u32(preset.session)
            payload.u32(preset.seq)
            try payload.str(preset.name)
            return Self.wrap(type: 13, payload: payload.data)
        case .chrome(let command):
            var payload = ByteWriter()
            payload.u32(command.session)
            payload.u32(command.seq)
            payload.u8(command.op.rawValue)
            payload.u16(command.index)
            payload.u16(command.windowIndex)
            payload.f64(command.dx)
            payload.f64(command.dy)
            return Self.wrap(type: 14, payload: payload.data)
        }
    }

    /// Returns nil for a well-framed message of an unknown type so a newer peer can be ignored.
    /// Throws on truncated, oversized, or inconsistent frames. Callers must drop the connection on throw
    /// so the stream cannot desynchronize.
    public static func decode(_ data: Data) throws -> XAInputMessage? {
        guard data.count <= FrameLimits.input.maxPayload else { throw ProtocolError.tooLarge }
        var reader = ByteReader(data: data)
        let version = try reader.u8()
        guard version == 1 else { throw ProtocolError.badVersion }
        let type = try reader.u8()
        _ = try reader.u16()
        let length = try reader.u32()
        guard Int(length) == reader.remaining else { throw ProtocolError.lengthMismatch }
        switch type {
        case 1:
            let hello = XAHello(
                protocolVersion: try reader.u16(),
                token: try reader.str(),
                deviceName: try reader.str(),
                deviceID: try reader.str(),
                flags: try reader.u8()
            )
            return .hello(hello)
        case 2:
            let accepted = try reader.u8() == 1
            let session = try reader.u32()
            let reason = try reader.str()
            return .helloAck(XAHelloAck(accepted: accepted, session: session, reason: reason))
        case 3:
            let session = try reader.u32()
            let seq = try reader.u32()
            guard let phase = XAMousePhase(rawValue: try reader.u8()),
                  let button = XAMouseButton(rawValue: try reader.u8()),
                  let space = XAPointerSpace(rawValue: try reader.u8()) else { throw ProtocolError.badEnum }
            _ = try reader.u8()
            return .mouse(XAMouse(session: session, seq: seq, phase: phase, button: button, x: try reader.f64(), y: try reader.f64(), space: space))
        case 4:
            let session = try reader.u32()
            let seq = try reader.u32()
            let dx = try reader.f64()
            let dy = try reader.f64()
            let inertia = try reader.u8() == 1
            return .scroll(XAScroll(session: session, seq: seq, dxPixels: dx, dyPixels: dy, inertia: inertia))
        case 5:
            let session = try reader.u32()
            let seq = try reader.u32()
            guard let phase = XAKeyPhase(rawValue: try reader.u8()) else { throw ProtocolError.badEnum }
            _ = try reader.u8()
            let code = try reader.u16()
            let mods = XAModifierMask(rawValue: UInt8(truncatingIfNeeded: try reader.u32()))
            let text = try reader.str()
            return .key(XAKey(session: session, seq: seq, phase: phase, keyCode: code, modifiers: mods, text: text))
        case 6:
            let session = try reader.u32()
            let seq = try reader.u32()
            let mask = XAModifierMask(rawValue: try reader.u8())
            let down = try reader.u8() == 1
            return .modifier(XAModifier(session: session, seq: seq, mask: mask, down: down))
        case 7:
            return .ping(XAPing(session: try reader.u32(), clientUnixMs: try reader.u64()))
        case 8:
            return .pong(XAPong(session: try reader.u32(), clientUnixMs: try reader.u64(), hostUnixMs: try reader.u64()))
        case 9:
            return .release(XARelease(session: try reader.u32(), seq: try reader.u32()))
        case 10:
            let session = try reader.u32()
            let seq = try reader.u32()
            let revision = try reader.u64()
            guard let kind = ClipboardKind(rawValue: try reader.u8()) else { throw ProtocolError.badEnum }
            switch kind {
            case .text:
                let text = try reader.str(maxBytes: XAClipboard.maxTextBytes)
                return .clipboard(XAClipboard(session: session, seq: seq, revision: revision, text: text, kind: .text))
            case .imagePNG:
                let count = Int(try reader.u32())
                guard count > 0, count <= XAClipboard.maxImageBytes, count == reader.remaining else { throw ProtocolError.tooLarge }
                let image = reader.data.subdata(in: reader.offset..<(reader.offset + count))
                return .clipboard(XAClipboard(session: session, seq: seq, revision: revision, text: "", kind: .imagePNG, image: image))
            }
        case 11:
            let session = try reader.u32()
            let seq = try reader.u32()
            guard let action = WindowAction(rawValue: try reader.u8()) else { throw ProtocolError.badEnum }
            return .window(XAWindowCommand(session: session, seq: seq, action: action))
        case 12:
            let session = try reader.u32()
            let sampleRate = try reader.u32()
            let channels = try reader.u16()
            let codecRaw = try reader.u16()
            guard let codec = XAAudioCodec(rawValue: UInt8(codecRaw)) else { throw ProtocolError.badEnum }
            let hostTimeMs = try reader.f64()
            let count = Int(try reader.u32())
            guard count <= XAAudio.maxBytes, count == reader.remaining else { throw ProtocolError.tooLarge }
            let bytes = reader.data.subdata(in: reader.offset..<(reader.offset + count))
            return .audio(XAAudio(session: session, sampleRate: sampleRate, channels: channels, pcm: bytes, codec: codec, hostTimeMs: hostTimeMs))
        case 13:
            let session = try reader.u32()
            let seq = try reader.u32()
            let name = try reader.str()
            return .preset(XAPresetCommand(session: session, seq: seq, name: name))
        case 14:
            let session = try reader.u32()
            let seq = try reader.u32()
            guard let op = ChromeOp(rawValue: try reader.u8()) else { throw ProtocolError.badEnum }
            let index = try reader.u16()
            let windowIndex = try reader.u16()
            let dx = try reader.f64()
            let dy = try reader.f64()
            return .chrome(XAChromeCommand(session: session, seq: seq, op: op, index: index, windowIndex: windowIndex, dx: dx, dy: dy))
        default:
            return nil
        }
    }

    private static func wrap(type: UInt8, payload: Data) -> Data {
        var writer = ByteWriter()
        writer.u8(1)
        writer.u8(type)
        writer.u16(0)
        writer.u32(UInt32(payload.count))
        writer.bytes(payload)
        return writer.data
    }
}

public struct LegacyHello: Equatable {
    public var pixelsWide: Int
    public var pixelsHigh: Int
    public var scale: Double
    public var device: String
    public var id: String
    public var orientation: String
    public init(pixelsWide: Int, pixelsHigh: Int, scale: Double, device: String, id: String, orientation: String) {
        self.pixelsWide = pixelsWide
        self.pixelsHigh = pixelsHigh
        self.scale = scale
        self.device = device
        self.id = id
        self.orientation = orientation
    }
}

public struct CursorImage: Equatable {
    public var id: String
    public var png: Data
    public init(id: String, png: Data) {
        self.id = id
        self.png = png
    }
}

public struct FrameAck: Equatable {
    public var seq: UInt64
    public var captureMs: Double
    public var receiveMs: Double
    public var enqueueMs: Double
    public init(seq: UInt64, captureMs: Double, receiveMs: Double, enqueueMs: Double) {
        self.seq = seq
        self.captureMs = captureMs
        self.receiveMs = receiveMs
        self.enqueueMs = enqueueMs
    }
}

public enum ThermalBucket: String, Equatable, Codable {
    case nominal, fair, serious, critical, unknown
    public static func from(processInfoRawValue: Int) -> ThermalBucket {
        switch processInfoRawValue {
        case 0: return .nominal
        case 1: return .fair
        case 2: return .serious
        case 3: return .critical
        default: return .unknown
        }
    }
}

public struct HealthReport: Equatable {
    public var thermal: ThermalBucket
    public var batteryFraction: Double?
    public var batteryState: String
    public var fpsDelivered: Double
    public var decodeFails: Int
    public init(thermal: ThermalBucket, batteryFraction: Double?, batteryState: String, fpsDelivered: Double, decodeFails: Int) {
        self.thermal = thermal
        self.batteryFraction = batteryFraction
        self.batteryState = batteryState
        self.fpsDelivered = fpsDelivered
        self.decodeFails = decodeFails
    }
}

public struct StreamAnnouncement: Equatable {
    public var preset: String
    public var width: Int
    public var height: Int
    public var fps: Int
    public var bitrate: Int
    public var experimental: Bool
    public init(preset: String, width: Int, height: Int, fps: Int, bitrate: Int, experimental: Bool) {
        self.preset = preset
        self.width = width
        self.height = height
        self.fps = fps
        self.bitrate = bitrate
        self.experimental = experimental
    }
}

public struct XAMetrics: Equatable {
    public var captureToAckMs: Double?
    public var encodeMs: Double?
    public init(captureToAckMs: Double?, encodeMs: Double?) {
        self.captureToAckMs = captureToAckMs
        self.encodeMs = encodeMs
    }
}

public enum VideoControlMessage: Equatable {
    case hello(LegacyHello)
    case touch(phase: String, x: Double, y: Double)
    case scroll(dx: Double, dy: Double)
    case ping(t: Double)
    case pong(t: Double, mt: Double)
    case cursor(x: Double, y: Double, visible: Bool)
    case cursorImage(CursorImage)
    case xaHello
    case frameAck(FrameAck)
    case health(HealthReport)
    case decodeFailed(preset: String)
    case xaStream(StreamAnnouncement)
    case xaMetrics(XAMetrics)
    case xaWindows(String)
    case xaMenus(String)
    case xaFront(String)
    case ignored

    public static let maxCursorPNG = 65_536
    public static let maxCursorBase64 = 100_000

    public func jsonData() -> Data? {
        let object: [String: Any]
        switch self {
        case .hello(let hello):
            object = [
                "type": "hello",
                "pixelsWide": hello.pixelsWide,
                "pixelsHigh": hello.pixelsHigh,
                "scale": hello.scale,
                "device": hello.device,
                "id": hello.id,
                "orientation": hello.orientation,
            ]
        case .touch(let phase, let x, let y):
            object = ["type": "touch", "phase": phase, "x": x, "y": y]
        case .scroll(let dx, let dy):
            object = ["type": "scroll", "dx": dx, "dy": dy]
        case .ping(let t):
            object = ["type": "ping", "t": t]
        case .pong(let t, let mt):
            object = ["type": "pong", "t": t, "mt": mt]
        case .cursor(let x, let y, let visible):
            object = ["type": "cursor", "x": x, "y": y, "v": visible ? 1 : 0]
        case .cursorImage(let image):
            object = ["type": "cursorImg", "id": image.id, "png": image.png.base64EncodedString()]
        case .xaHello:
            object = ["type": "xa.hello", "host": "XA Display Host", "pv": 1]
        case .frameAck(let ack):
            object = ["type": "frameAck", "seq": Int(ack.seq), "captureMs": ack.captureMs, "receiveMs": ack.receiveMs, "enqueueMs": ack.enqueueMs]
        case .health(let health):
            var object: [String: Any] = [
                "type": "health",
                "thermal": health.thermal.rawValue,
                "batteryState": health.batteryState,
                "fps": health.fpsDelivered,
                "decodeFails": health.decodeFails,
            ]
            if let fraction = health.batteryFraction { object["battery"] = fraction }
            return JSON.data(object)
        case .decodeFailed(let preset):
            object = ["type": "decodeFailed", "preset": preset]
        case .xaStream(let stream):
            object = [
                "type": "xa.stream", "preset": stream.preset, "w": stream.width, "h": stream.height,
                "fps": stream.fps, "bitrate": stream.bitrate, "experimental": stream.experimental,
            ]
        case .xaMetrics(let metrics):
            var object: [String: Any] = ["type": "xa.metrics"]
            if let value = metrics.captureToAckMs { object["captureToAckMs"] = value }
            if let value = metrics.encodeMs { object["encodeMs"] = value }
            return JSON.data(object)
        case .xaWindows(let body):
            object = ["type": "xa.windows", "body": body]
        case .xaMenus(let body):
            object = ["type": "xa.menus", "body": body]
        case .xaFront(let bundle):
            object = ["type": "xa.front", "bundle": bundle]
        case .ignored:
            return nil
        }
        return JSON.data(object)
    }

    public static func parse(_ data: Data) -> VideoControlMessage {
        guard data.count <= 32_768, PayloadKind.classify(data) == .controlJSON,
              let obj = JSON.object(data), obj.count <= 32,
              let type = JSON.string(obj["type"]), type.count <= 64 else { return .ignored }
        switch type {
        case "hello":
            guard let wide = JSON.int(obj["pixelsWide"]), let high = JSON.int(obj["pixelsHigh"]) else { return .ignored }
            return .hello(LegacyHello(
                pixelsWide: wide,
                pixelsHigh: high,
                scale: JSON.double(obj["scale"]) ?? 1,
                device: JSON.string(obj["device"]) ?? "iPad",
                id: JSON.string(obj["id"]) ?? "",
                orientation: JSON.string(obj["orientation"]) ?? "landscape"
            ))
        case "touch":
            guard let phase = JSON.string(obj["phase"]) else { return .ignored }
            return .touch(phase: phase, x: JSON.double(obj["x"]) ?? 0, y: JSON.double(obj["y"]) ?? 0)
        case "scroll":
            return .scroll(dx: JSON.double(obj["dx"]) ?? 0, dy: JSON.double(obj["dy"]) ?? 0)
        case "ping":
            return .ping(t: JSON.double(obj["t"]) ?? 0)
        case "pong":
            return .pong(t: JSON.double(obj["t"]) ?? 0, mt: JSON.double(obj["mt"]) ?? 0)
        case "cursor":
            let visible = (JSON.int(obj["v"]) ?? 0) == 1
            return .cursor(x: JSON.double(obj["x"]) ?? 0, y: JSON.double(obj["y"]) ?? 0, visible: visible)
        case "cursorImg":
            guard let b64 = JSON.string(obj["png"]), b64.count <= maxCursorBase64,
                  let png = Data(base64Encoded: b64), png.count <= maxCursorPNG, !png.isEmpty else { return .ignored }
            let id = JSON.string(obj["id"]) ?? "default"
            return .cursorImage(CursorImage(id: id, png: png))
        case "xa.hello":
            return .xaHello
        case "frameAck":
            guard let capture = JSON.double(obj["captureMs"]),
                  let receive = JSON.double(obj["receiveMs"]),
                  let enqueue = JSON.double(obj["enqueueMs"]) else { return .ignored }
            let seq = UInt64(JSON.int(obj["seq"]) ?? 0)
            return .frameAck(FrameAck(seq: seq, captureMs: capture, receiveMs: receive, enqueueMs: enqueue))
        case "health":
            let thermal = ThermalBucket(rawValue: JSON.string(obj["thermal"]) ?? "") ?? .unknown
            let battery = JSON.double(obj["battery"])
            return .health(HealthReport(
                thermal: thermal,
                batteryFraction: battery,
                batteryState: JSON.string(obj["batteryState"]) ?? "unknown",
                fpsDelivered: JSON.double(obj["fps"]) ?? 0,
                decodeFails: JSON.int(obj["decodeFails"]) ?? 0
            ))
        case "decodeFailed":
            return .decodeFailed(preset: JSON.string(obj["preset"]) ?? "")
        case "xa.stream":
            return .xaStream(StreamAnnouncement(
                preset: JSON.string(obj["preset"]) ?? "",
                width: JSON.int(obj["w"]) ?? 0,
                height: JSON.int(obj["h"]) ?? 0,
                fps: JSON.int(obj["fps"]) ?? 0,
                bitrate: JSON.int(obj["bitrate"]) ?? 0,
                experimental: JSON.bool(obj["experimental"]) ?? false
            ))
        case "xa.metrics":
            return .xaMetrics(XAMetrics(
                captureToAckMs: JSON.double(obj["captureToAckMs"]),
                encodeMs: JSON.double(obj["encodeMs"])
            ))
        case "xa.windows":
            return .xaWindows(JSON.string(obj["body"]) ?? "")
        case "xa.menus":
            return .xaMenus(JSON.string(obj["body"]) ?? "")
        case "xa.front":
            return .xaFront(JSON.string(obj["bundle"]) ?? "")
        default:
            return .ignored
        }
    }
}

public struct CursorCache {
    public var maxEntries: Int
    public var maxBytes: Int
    private var order: [String] = []
    private var images: [String: Data] = [:]

    public init(maxEntries: Int = 8, maxBytes: Int = VideoControlMessage.maxCursorPNG) {
        self.maxEntries = maxEntries
        self.maxBytes = maxBytes
    }

    public mutating func store(id: String, png: Data) -> Bool {
        guard png.count <= maxBytes, !id.isEmpty else { return false }
        if let existing = order.firstIndex(of: id) {
            order.remove(at: existing)
        }
        images[id] = png
        order.append(id)
        while order.count > maxEntries {
            let evicted = order.removeFirst()
            images.removeValue(forKey: evicted)
        }
        return true
    }

    public func image(id: String) -> Data? { images[id] }
    public var count: Int { images.count }
}

/// Video-channel touch JSON has no pairing token. The Mac host must not turn it into CGEvents.
public enum LegacyInputPolicy {
    public static let acceptsUnauthenticatedVideoInput = false
}
