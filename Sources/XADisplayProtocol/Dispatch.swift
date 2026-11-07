import Foundation

public enum PairingDecision: Equatable {
    case accept
    case reject(PairingRejectReason)
}

public enum PairingRejectReason: Equatable {
    case empty
    case mismatch
}

public enum PairingGate {
    public static func evaluate(presented: String, expected: String) -> PairingDecision {
        let presented = normalize(presented)
        let expected = normalize(expected)
        if presented.isEmpty || expected.isEmpty { return .reject(.empty) }
        if !constantTimeEquals(presented, expected) { return .reject(.mismatch) }
        return .accept
    }

    public static func normalize(_ token: String) -> String {
        let filtered = token.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) && $0 != "-" }
        return String(String.UnicodeScalarView(filtered)).uppercased()
    }

    static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        var diff = left.count ^ right.count
        let count = max(left.count, right.count)
        if count == 0 { return false }
        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            diff |= Int(l ^ r)
        }
        return diff == 0
    }
}

public enum PairingToken {
    public static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    public static func make<R: RandomNumberGenerator>(using rng: inout R) -> String {
        var characters: [Character] = []
        characters.reserveCapacity(9)
        for index in 0..<8 {
            if index == 4 { characters.append("-") }
            let pick = Int(rng.next() % UInt64(alphabet.count))
            characters.append(alphabet[pick])
        }
        return String(characters)
    }

    public static func make() -> String {
        var rng = SystemRandomNumberGenerator()
        return make(using: &rng)
    }
}

public struct RateLimiter {
    public var maxPerSecond: Int
    private var windowStart: Double?
    private var count = 0

    public init(maxPerSecond: Int) {
        self.maxPerSecond = max(1, maxPerSecond)
    }

    public mutating func allow(now: Double) -> Bool {
        if let start = windowStart, now - start < 1 {
            if count >= maxPerSecond { return false }
            count += 1
            return true
        }
        windowStart = now
        count = 1
        return true
    }
}

public enum PostedMousePhase: Equatable {
    case move, down, up, drag
}

public enum PostedEvent: Equatable {
    case mouse(phase: PostedMousePhase, button: XAMouseButton, global: XAPoint)
    case scroll(dxPoints: Double, dyPoints: Double)
    case key(phase: XAKeyPhase, keyCode: UInt16, modifiers: XAModifierMask, text: String)
    case modifier(bit: XAModifierMask, down: Bool)
    case clipboard(text: String, revision: UInt64)
    case window(WindowAction)
    case chrome(op: UInt8, index: UInt16, windowIndex: UInt16, dx: Double, dy: Double)
}

public enum DispatchOutcome: Equatable {
    case post([PostedEvent])
    case reply(XAInputMessage)
    case postAndReply([PostedEvent], XAInputMessage)
    case drop
}

/// Turns paired input messages into pointer, scroll, and key events in the virtual display's global frame.
/// A wrong token, a stale session, or a replayed sequence number never produces an injected event.
/// Disconnect always yields the button, key, and modifier releases needed to avoid stuck input.
public struct InputDispatcher {
    public var expectedToken: String
    public var displayFrame: XARect
    public var videoPixelSize: XASize
    public var maxInputPerSecond: Int
    public var requirePairing: Bool
    public var clipboardEnabled: Bool
    public var windowActionsEnabled: Bool
    public var sessionGenerator: () -> UInt32
    public private(set) var armed = false
    public private(set) var session: UInt32 = 0
    public private(set) var cursorNormalized = XAPoint(x: 0.5, y: 0.5)

    private var lastSeq: UInt32 = 0
    private var heldButtons = Set<XAMouseButton>()
    private var modifiers = XAModifierMask()
    private var heldKeys = Set<UInt16>()
    private var lastGlobal = XAPoint.zero
    private var limiter: RateLimiter
    private var fallbackSession: UInt32 = 1

    public init(
        expectedToken: String, displayFrame: XARect = XARect(x: 0, y: 0, width: 0, height: 0), videoPixelSize: XASize = .zero, maxInputPerSecond: Int = 500, requirePairing: Bool = true,
        clipboardEnabled: Bool = false, windowActionsEnabled: Bool = false
    ) {
        self.expectedToken = expectedToken
        self.displayFrame = displayFrame
        self.videoPixelSize = videoPixelSize
        self.maxInputPerSecond = maxInputPerSecond
        self.requirePairing = requirePairing
        self.clipboardEnabled = clipboardEnabled
        self.windowActionsEnabled = windowActionsEnabled
        self.sessionGenerator = { 0 }
        self.limiter = RateLimiter(maxPerSecond: maxInputPerSecond)
        self.lastGlobal = CoordinateMapper.globalPoint(normalized: XAPoint(x: 0.5, y: 0.5), displayFrame: displayFrame)
    }

    public mutating func handle(_ message: XAInputMessage, hostNowMs: Double) -> DispatchOutcome {
        switch message {
        case .hello(let hello):
            let released = releaseHeld()
            armed = false
            lastSeq = 0
            session = 0
            let versionOK = hello.protocolVersion == XADisplayProtocolInfo.inputVersion
            let decision = PairingGate.evaluate(presented: hello.token, expected: expectedToken)
            let mustPair = requirePairing || (hello.flags & XAHello.flagRequiresPairing) != 0
            let pairingOK =
                !mustPair
                || {
                    if case .accept = decision { return true }
                    return false
                }()
            let ack: XAHelloAck
            if versionOK, pairingOK {
                var generated = sessionGenerator()
                if generated == 0 {
                    generated = fallbackSession
                    fallbackSession &+= 1
                    if fallbackSession == 0 { fallbackSession = 1 }
                }
                session = generated
                armed = true
                ack = XAHelloAck(accepted: true, session: session, reason: "ok")
            } else if !versionOK {
                ack = XAHelloAck(accepted: false, session: 0, reason: "version")
            } else if case .reject(.empty) = decision {
                ack = XAHelloAck(accepted: false, session: 0, reason: "empty")
            } else {
                ack = XAHelloAck(accepted: false, session: 0, reason: "token")
            }
            let reply = XAInputMessage.helloAck(ack)
            if released.isEmpty { return .reply(reply) }
            return .postAndReply(released, reply)

        case .ping(let ping):
            let pong = XAPong(session: armed ? session : 0, clientUnixMs: ping.clientUnixMs, hostUnixMs: UInt64(max(0, hostNowMs)))
            return .reply(.pong(pong))

        case .mouse(let mouse):
            guard accept(session: mouse.session, seq: mouse.seq, hostNowMs: hostNowMs, limited: mouse.phase == .move) else { return .drop }
            return .post(mouseEvents(mouse))

        case .scroll(let scroll):
            guard accept(session: scroll.session, seq: scroll.seq, hostNowMs: hostNowMs, limited: true) else { return .drop }
            guard videoPixelSize.width > 0, videoPixelSize.height > 0, displayFrame.width > 0, displayFrame.height > 0 else { return .drop }
            let dx = scroll.dxPixels * (displayFrame.width / videoPixelSize.width)
            let dy = scroll.dyPixels * (displayFrame.height / videoPixelSize.height)
            return .post([.scroll(dxPoints: dx, dyPoints: dy)])

        case .key(let key):
            guard accept(session: key.session, seq: key.seq, hostNowMs: hostNowMs, limited: false) else { return .drop }
            if key.phase == .down, key.keyCode != 0 { heldKeys.insert(key.keyCode) }
            if key.phase == .up { heldKeys.remove(key.keyCode) }
            return .post([.key(phase: key.phase, keyCode: key.keyCode, modifiers: key.modifiers, text: key.text)])

        case .modifier(let modifier):
            guard accept(session: modifier.session, seq: modifier.seq, hostNowMs: hostNowMs, limited: false) else { return .drop }
            var events: [PostedEvent] = []
            for bit in modifier.mask.individualBits {
                let already = modifiers.contains(bit)
                if modifier.down && !already {
                    modifiers.insert(bit)
                    events.append(.modifier(bit: bit, down: true))
                } else if !modifier.down && already {
                    modifiers.remove(bit)
                    events.append(.modifier(bit: bit, down: false))
                }
            }
            return .post(events)

        case .release(let release):
            guard armed, release.session == session else { return .drop }
            if release.seq <= lastSeq { return .drop }
            lastSeq = release.seq
            return .post(releaseHeld())

        case .clipboard(let clip):
            guard clipboardEnabled, clip.kind == .text else { return .drop }
            guard clip.text.utf8.count <= XAClipboard.maxTextBytes else { return .drop }
            guard accept(session: clip.session, seq: clip.seq, hostNowMs: hostNowMs, limited: false) else { return .drop }
            return .post([.clipboard(text: clip.text, revision: clip.revision)])

        case .window(let command):
            guard windowActionsEnabled else { return .drop }
            guard accept(session: command.session, seq: command.seq, hostNowMs: hostNowMs, limited: false) else { return .drop }
            return .post([.window(command.action)])

        case .chrome(let command):
            guard windowActionsEnabled else { return .drop }
            guard accept(session: command.session, seq: command.seq, hostNowMs: hostNowMs, limited: false) else { return .drop }
            return .post([.chrome(op: command.op.rawValue, index: command.index, windowIndex: command.windowIndex, dx: command.dx, dy: command.dy)])

        case .helloAck, .pong, .audio, .preset:
            return .drop
        }
    }

    public mutating func disconnect() -> [PostedEvent] {
        let events = releaseHeld()
        armed = false
        session = 0
        lastSeq = 0
        return events
    }

    public mutating func releaseHeld() -> [PostedEvent] {
        var events: [PostedEvent] = []
        for button in heldButtons.sorted(by: { $0.rawValue < $1.rawValue }) {
            events.append(.mouse(phase: .up, button: button, global: lastGlobal))
        }
        for bit in modifiers.individualBits {
            events.append(.modifier(bit: bit, down: false))
        }
        let mask = modifiers
        for code in heldKeys.sorted() {
            events.append(.key(phase: .up, keyCode: code, modifiers: mask, text: ""))
        }
        heldButtons.removeAll()
        modifiers = []
        heldKeys.removeAll()
        return events
    }

    private mutating func accept(session messageSession: UInt32, seq: UInt32, hostNowMs: Double, limited: Bool) -> Bool {
        guard armed, messageSession == session, seq > lastSeq else { return false }
        lastSeq = seq
        if limited && !limiter.allow(now: hostNowMs / 1000) { return false }
        return true
    }

    private mutating func mouseEvents(_ mouse: XAMouse) -> [PostedEvent] {
        let mapped: XAPoint?
        switch mouse.space {
        case .absoluteNormalized:
            let nx = min(1, max(0, mouse.x))
            let ny = min(1, max(0, mouse.y))
            cursorNormalized = XAPoint(x: nx, y: ny)
            mapped = globalIfPossible(cursorNormalized)
        case .relativeNormalized:
            cursorNormalized.x = min(1, max(0, cursorNormalized.x + mouse.x))
            cursorNormalized.y = min(1, max(0, cursorNormalized.y + mouse.y))
            mapped = globalIfPossible(cursorNormalized)
        }
        if mouse.phase == .up {
            heldButtons.remove(mouse.button)
            let point = mapped ?? lastGlobal
            lastGlobal = point
            return [.mouse(phase: .up, button: mouse.button, global: point)]
        }
        guard let point = mapped else {
            if mouse.phase == .down { return [] }
            return []
        }
        lastGlobal = point
        switch mouse.phase {
        case .down:
            heldButtons.insert(mouse.button)
            return [.mouse(phase: .down, button: mouse.button, global: point)]
        case .up:
            return [.mouse(phase: .up, button: mouse.button, global: point)]
        case .move:
            if heldButtons.contains(mouse.button) || !heldButtons.isEmpty {
                let button = heldButtons.contains(mouse.button) ? mouse.button : (heldButtons.sorted { $0.rawValue < $1.rawValue }.first ?? mouse.button)
                return [.mouse(phase: .drag, button: button, global: point)]
            }
            return [.mouse(phase: .move, button: mouse.button, global: point)]
        }
    }

    private func globalIfPossible(_ normalized: XAPoint) -> XAPoint? {
        guard displayFrame.width > 0, displayFrame.height > 0 else { return nil }
        return CoordinateMapper.globalPoint(normalized: normalized, displayFrame: displayFrame)
    }
}
