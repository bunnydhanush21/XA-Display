import Foundation

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
    case xaBattery(text: String, heat: Bool)
    case xaSettings(String)
    case xaNack(String)
    case xaOrient(orientation: String, mode: String, letterbox: Bool)
    case xaAuth(id: String, proof: String)
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
                "orientation": hello.orientation
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
                "decodeFails": health.decodeFails
            ]
            if let fraction = health.batteryFraction { object["battery"] = fraction }
            return JSON.data(object)
        case .decodeFailed(let preset):
            object = ["type": "decodeFailed", "preset": preset]
        case .xaStream(let stream):
            object = [
                "type": "xa.stream", "preset": stream.preset, "w": stream.width, "h": stream.height,
                "fps": stream.fps, "bitrate": stream.bitrate, "experimental": stream.experimental
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
        case .xaBattery(let text, let heat):
            object = ["type": "xa.battery", "text": text, "heat": heat]
        case .xaSettings(let body):
            object = ["type": "xa.settings", "body": body]
        case .xaNack(let body):
            object = ["type": "xa.nack", "body": body]
        case .xaOrient(let orientation, let mode, let letterbox):
            object = ["type": "xa.orient", "o": orientation, "mode": mode, "letterbox": letterbox]
        case .xaAuth(let id, let proof):
            object = ["type": "xa.auth", "id": id, "proof": proof]
        case .ignored:
            return nil
        }
        return JSON.data(object)
    }

    public static func parse(_ data: Data) -> VideoControlMessage {
        guard data.count <= 32_768, PayloadKind.classify(data) == .controlJSON,
            let obj = JSON.object(data), obj.count <= 32,
            let type = JSON.string(obj["type"]), type.count <= 64
        else { return .ignored }
        switch type {
        case "hello":
            guard let wide = JSON.int(obj["pixelsWide"]), let high = JSON.int(obj["pixelsHigh"]) else { return .ignored }
            return .hello(
                LegacyHello(
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
                let png = Data(base64Encoded: b64), png.count <= maxCursorPNG, !png.isEmpty
            else { return .ignored }
            let id = JSON.string(obj["id"]) ?? "default"
            return .cursorImage(CursorImage(id: id, png: png))
        case "xa.hello":
            return .xaHello
        case "frameAck":
            guard let capture = JSON.double(obj["captureMs"]),
                let receive = JSON.double(obj["receiveMs"]),
                let enqueue = JSON.double(obj["enqueueMs"])
            else { return .ignored }
            let seq = UInt64(JSON.int(obj["seq"]) ?? 0)
            return .frameAck(FrameAck(seq: seq, captureMs: capture, receiveMs: receive, enqueueMs: enqueue))
        case "health":
            let thermal = ThermalBucket(rawValue: JSON.string(obj["thermal"]) ?? "") ?? .unknown
            let battery = JSON.double(obj["battery"])
            return .health(
                HealthReport(
                    thermal: thermal,
                    batteryFraction: battery,
                    batteryState: JSON.string(obj["batteryState"]) ?? "unknown",
                    fpsDelivered: JSON.double(obj["fps"]) ?? 0,
                    decodeFails: JSON.int(obj["decodeFails"]) ?? 0
                ))
        case "decodeFailed":
            return .decodeFailed(preset: JSON.string(obj["preset"]) ?? "")
        case "xa.stream":
            return .xaStream(
                StreamAnnouncement(
                    preset: JSON.string(obj["preset"]) ?? "",
                    width: JSON.int(obj["w"]) ?? 0,
                    height: JSON.int(obj["h"]) ?? 0,
                    fps: JSON.int(obj["fps"]) ?? 0,
                    bitrate: JSON.int(obj["bitrate"]) ?? 0,
                    experimental: JSON.bool(obj["experimental"]) ?? false
                ))
        case "xa.metrics":
            return .xaMetrics(
                XAMetrics(
                    captureToAckMs: JSON.double(obj["captureToAckMs"]),
                    encodeMs: JSON.double(obj["encodeMs"])
                ))
        case "xa.windows":
            return .xaWindows(JSON.string(obj["body"]) ?? "")
        case "xa.menus":
            return .xaMenus(JSON.string(obj["body"]) ?? "")
        case "xa.front":
            return .xaFront(JSON.string(obj["bundle"]) ?? "")
        case "xa.battery":
            return .xaBattery(text: JSON.string(obj["text"]) ?? "", heat: JSON.bool(obj["heat"]) ?? false)
        case "xa.settings":
            return .xaSettings(JSON.string(obj["body"]) ?? "")
        case "xa.nack":
            return .xaNack(JSON.string(obj["body"]) ?? "")
        case "xa.orient":
            return .xaOrient(
                orientation: JSON.string(obj["o"]) ?? "landscape",
                mode: JSON.string(obj["mode"]) ?? "resolution",
                letterbox: JSON.bool(obj["letterbox"]) ?? false
            )
        case "xa.auth":
            return .xaAuth(id: JSON.string(obj["id"]) ?? "", proof: JSON.string(obj["proof"]) ?? "")
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
