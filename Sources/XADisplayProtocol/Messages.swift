import Foundation

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
    case media(XAMediaCommand)
    case nowPlaying(XANowPlaying)

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
            payload.u8(0)
            payload.u8(0)
            payload.u8(0)
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
        case .media(let command):
            var payload = ByteWriter()
            payload.u32(command.session)
            payload.u32(command.seq)
            payload.u8(command.action.rawValue)
            payload.f64(command.scrub)
            return Self.wrap(type: 15, payload: payload.data)
        case .nowPlaying(let info):
            guard info.artworkPNG.count <= XANowPlaying.maxArtworkBytes else { throw ProtocolError.tooLarge }
            var payload = ByteWriter()
            payload.u32(info.session)
            try payload.str(info.appName)
            try payload.str(info.title)
            try payload.str(info.artist)
            payload.f64(info.position)
            payload.f64(info.duration)
            payload.u32(UInt32(info.artworkPNG.count))
            payload.bytes(info.artworkPNG)
            return Self.wrap(type: 16, payload: payload.data)
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
                let space = XAPointerSpace(rawValue: try reader.u8())
            else { throw ProtocolError.badEnum }
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
        case 15:
            let session = try reader.u32()
            let seq = try reader.u32()
            guard let action = MediaAction(rawValue: try reader.u8()) else { throw ProtocolError.badEnum }
            let scrub = try reader.f64()
            return .media(XAMediaCommand(session: session, seq: seq, action: action, scrub: scrub))
        case 16:
            let session = try reader.u32()
            let appName = try reader.str()
            let title = try reader.str()
            let artist = try reader.str()
            let position = try reader.f64()
            let duration = try reader.f64()
            let count = Int(try reader.u32())
            guard count <= XANowPlaying.maxArtworkBytes, count == reader.remaining else { throw ProtocolError.tooLarge }
            let artwork = count == 0 ? Data() : reader.data.subdata(in: reader.offset..<(reader.offset + count))
            return .nowPlaying(XANowPlaying(session: session, appName: appName, title: title, artist: artist, position: position, duration: duration, artworkPNG: artwork))
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
