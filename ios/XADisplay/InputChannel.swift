import Foundation
import Network
import UIKit
import XADisplayProtocol

protocol InputChannelDelegate: AnyObject {
    func inputChannel(_ channel: InputChannel, armed: Bool, reason: String)
    func inputChannel(_ channel: InputChannel, clipboard text: String, revision: UInt64)
    func inputChannel(_ channel: InputChannel, audio: XAAudio)
    func inputChannel(_ channel: InputChannel, roundTripMs: Double)
    func inputChannel(_ channel: InputChannel, clockOffsetClientMinusHost: Double)
}

final class InputChannel {
    weak var delegate: InputChannelDelegate?
    private(set) var armed = false
    private var session: UInt32 = 0
    private var seq: UInt32 = 0
    private var listener: NWListener?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "xa.input")
    private var parser = FrameParser(limits: .input)
    private var userPaused = false
    var token = ""
    var deviceName = "iPad"
    var requirePairing = true

    func start() {
        userPaused = false
        queue.async { self.listen() }
    }

    func pause() {
        userPaused = true
        queue.async {
            self.sendReleaseLocked()
            self.connection?.cancel()
            self.connection = nil
            self.armed = false
        }
    }

    func ensureListening() {
        guard !userPaused else { return }
        queue.async {
            self.connection?.cancel()
            self.connection = nil
            self.listener?.cancel()
            self.listener = nil
            self.parser = FrameParser(limits: .input)
            self.armed = false
            self.listen()
        }
    }

    func send(intent: InputIntent) {
        queue.async {
            guard self.armed else { return }
            for message in Self.messages(for: intent, session: self.session, nextSeq: { self.nextSeq() }) {
                self.send(message)
            }
        }
    }

    func sendClipboard(text: String, revision: UInt64) {
        queue.async {
            guard self.armed, ClipboardPolicy.accept(enabled: true, armed: true, utf8Count: text.utf8.count) else { return }
            self.send(.clipboard(XAClipboard(session: self.session, seq: self.nextSeq(), revision: revision, text: text)))
        }
    }

    func sendWindow(_ action: WindowAction) {
        queue.async {
            guard self.armed else { return }
            self.send(.window(XAWindowCommand(session: self.session, seq: self.nextSeq(), action: action)))
        }
    }

    func sendChrome(op: ChromeOp, index: UInt16, windowIndex: UInt16, dx: Double, dy: Double) {
        queue.async {
            guard self.armed else { return }
            let command = XAChromeCommand(session: self.session, seq: self.nextSeq(), op: op, index: index, windowIndex: windowIndex, dx: dx, dy: dy)
            self.send(.chrome(command))
        }
    }

    func sendRelease() {
        queue.async { self.sendReleaseLocked() }
    }

    private func sendReleaseLocked() {
        guard armed else { return }
        send(.release(XARelease(session: session, seq: nextSeq())))
        armed = false
    }

    private func nextSeq() -> UInt32 {
        seq &+= 1
        if seq == 0 { seq = 1 }
        return seq
    }

    private func listen() {
        guard !userPaused else { return }
        do {
            let tcp = NWProtocolTCP.Options()
            tcp.noDelay = true
            let params = NWParameters(tls: nil, tcp: tcp)
            params.allowLocalEndpointReuse = true
            guard let port = NWEndpoint.Port(rawValue: XADisplayProtocolInfo.inputPort) else { return }
            listener = try NWListener(using: params, on: port)
        } catch {
            return
        }
        listener?.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            if case .failed = state, !self.userPaused {
                self.queue.asyncAfter(deadline: .now() + 1) {
                    self.listener?.cancel()
                    self.listener = nil
                    self.listen()
                }
            }
        }
        listener?.start(queue: queue)
    }

    private func accept(_ connection: NWConnection) {
        self.connection?.cancel()
        self.connection = connection
        parser = FrameParser(limits: .input)
        armed = false
        session = 0
        seq = 0
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            if case .ready = state {
                self.sendHello()
            } else if case .failed = state {
                self.armed = false
            } else if case .cancelled = state {
                self.armed = false
            }
        }
        connection.start(queue: queue)
        receive(connection)
    }

    private func sendHello() {
        let flags: UInt8 = requirePairing ? XAHello.flagRequiresPairing : 0
        send(.hello(XAHello(
            protocolVersion: XADisplayProtocolInfo.inputVersion,
            token: token,
            deviceName: deviceName,
            deviceID: VideoReceiver.installID,
            flags: flags
        )))
    }

    private func receive(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                switch self.parser.append(data, now: Date().timeIntervalSince1970) {
                case .ok(let frames):
                    for frame in frames {
                        do {
                            if let message = try XAInputMessage.decode(frame) {
                                self.handle(message)
                            }
                        } catch {
                            connection.cancel()
                            return
                        }
                    }
                case .failed:
                    connection.cancel()
                    return
                }
            }
            if error != nil || isComplete { return }
            self.receive(connection)
        }
    }

    private func handle(_ message: XAInputMessage) {
        switch message {
        case .helloAck(let ack):
            armed = ack.accepted
            session = ack.session
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.inputChannel(self, armed: ack.accepted, reason: ack.reason)
            }
        case .pong(let pong):
            let now = Date().timeIntervalSince1970 * 1000
            let send = Double(pong.clientUnixMs)
            let host = Double(pong.hostUnixMs)
            if now >= send {
                let rtt = now - send
                let offset = AudioSyncMath.clockOffsetClientMinusHost(clientSendMs: send, hostMs: host, clientRecvMs: now)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.inputChannel(self, roundTripMs: rtt)
                    if let offset = offset {
                        self.delegate?.inputChannel(self, clockOffsetClientMinusHost: offset)
                    }
                }
            }
        case .clipboard(let clip):
            guard armed else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.inputChannel(self, clipboard: clip.text, revision: clip.revision)
            }
        case .audio(let audio):
            guard AudioPolicy.accept(enabled: true, armed: armed, byteCount: audio.pcm.count, channels: Int(audio.channels)) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.inputChannel(self, audio: audio)
            }
        default:
            break
        }
    }

    func sendPing() {
        queue.async {
            guard self.connection != nil else { return }
            self.send(.ping(XAPing(session: self.session, clientUnixMs: UInt64(Date().timeIntervalSince1970 * 1000))))
        }
    }

    private func send(_ message: XAInputMessage) {
        guard let connection = connection, let payload = try? message.encode() else { return }
        connection.send(content: LengthPrefixedFraming.encode(payload), completion: .contentProcessed { _ in })
    }

    private static func messages(for intent: InputIntent, session: UInt32, nextSeq: () -> UInt32) -> [XAInputMessage] {
        switch intent {
        case .mouse(let phase, let button, let x, let y, let space):
            return [.mouse(XAMouse(session: session, seq: nextSeq(), phase: phase, button: button, x: x, y: y, space: space))]
        case .scroll(let dx, let dy, let inertia):
            return [.scroll(XAScroll(session: session, seq: nextSeq(), dxPixels: dx, dyPixels: dy, inertia: inertia))]
        case .key(let phase, let code, let modifiers, let text):
            return [.key(XAKey(session: session, seq: nextSeq(), phase: phase, keyCode: code, modifiers: modifiers, text: text))]
        case .modifier(let mask, let down):
            return [.modifier(XAModifier(session: session, seq: nextSeq(), mask: mask, down: down))]
        case .release:
            return [.release(XARelease(session: session, seq: nextSeq()))]
        }
    }
}
