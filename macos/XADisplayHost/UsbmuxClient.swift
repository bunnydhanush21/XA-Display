import Darwin
import Foundation
import XADisplayProtocol

struct UsbmuxDevice {
    var deviceID: Int
    var connectionType: String
}

enum UsbmuxError: Error {
    case socket
    case timeout
    case badResponse
    case result(Int)
}

enum UsbmuxClient {
    static func listUSBDevices() -> [UsbmuxDevice] {
        guard let fd = openSocket() else { return [] }
        defer { close(fd) }
        guard sendPlist(["MessageType": "ListDevices"], tag: 1, fd: fd),
              let reply = readPlist(fd: fd),
              let list = reply["DeviceList"] as? [Any] else { return [] }
        var devices: [UsbmuxDevice] = []
        for item in list {
            guard let dict = item as? [String: Any] else { continue }
            let properties = dict["Properties"] as? [String: Any] ?? dict
            let type = (properties["ConnectionType"] as? String) ?? ""
            let id = (dict["DeviceID"] as? Int) ?? (properties["DeviceID"] as? Int) ?? (dict["DeviceID"] as? NSNumber)?.intValue ?? 0
            if type == "USB" && id != 0 {
                devices.append(UsbmuxDevice(deviceID: id, connectionType: type))
            }
        }
        return devices
    }

    static func connect(deviceID: Int, port: UInt16) -> Int32? {
        let candidates = UsbmuxPort.candidates(port)
        var index = 0
        while index < candidates.count {
            let candidate = candidates[index]
            index += 1
            guard let fd = openSocket() else { return nil }
            if attemptConnect(deviceID: deviceID, portNumber: Int(candidate), fd: fd) {
                return fd
            }
            close(fd)
        }
        return nil
    }

    private static func attemptConnect(deviceID: Int, portNumber: Int, fd: Int32) -> Bool {
        var body: [String: Any] = [:]
        body["MessageType"] = "Connect"
        body["DeviceID"] = deviceID
        body["PortNumber"] = portNumber
        if sendPlist(body, tag: 2, fd: fd) == false { return false }
        guard let reply = readPlist(fd: fd) else { return false }
        if let number = reply["Number"] as? Int {
            return number == 0
        }
        if let number = reply["Number"] as? NSNumber {
            return number.intValue == 0
        }
        return false
    }

    private static func openSocket() -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = "/var/run/usbmuxd"
        _ = withUnsafeMutablePointer(to: &address.sun_path) { tuple in
            tuple.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
                _ = strncpy(dest, path, 103)
            }
        }
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, length) }
        }
        if connected != 0 {
            close(fd)
            return nil
        }
        return fd
    }

    private static func sendPlist(_ object: [String: Any], tag: UInt32, fd: Int32) -> Bool {
        guard let payload = try? PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0) else { return false }
        var header = Data()
        func put(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { header.append(contentsOf: $0) }
        }
        put(UInt32(16 + payload.count))
        put(1)
        put(8)
        put(tag)
        header.append(payload)
        return header.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            var sent = 0
            while sent < raw.count {
                let n = write(fd, base.advanced(by: sent), raw.count - sent)
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
    }

    private static func readPlist(fd: Int32) -> [String: Any]? {
        guard let header = readExact(fd: fd, count: 16), header.count == 16 else { return nil }
        let length = header.withUnsafeBytes { raw -> Int in
            let value = raw.load(fromByteOffset: 0, as: UInt32.self)
            return Int(UInt32(littleEndian: value))
        }
        guard length >= 16, length < 1_000_000 else { return nil }
        guard let body = readExact(fd: fd, count: length - 16) else { return nil }
        return try? PropertyListSerialization.propertyList(from: body, options: [], format: nil) as? [String: Any]
    }

    private static func readExact(fd: Int32, count: Int) -> Data? {
        var data = Data(count: count)
        var got = 0
        let ok = data.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            while got < count {
                let n = read(fd, base.advanced(by: got), count - got)
                if n <= 0 { return false }
                got += n
            }
            return true
        }
        return ok ? data : nil
    }
}

final class FDStream {
    let fd: Int32
    var onData: ((Data) -> Void)?
    var onClose: (() -> Void)?
    private let queue = DispatchQueue(label: "xa.fd")
    private var source: DispatchSourceRead?
    private var closed = false

    init(fd: Int32) {
        self.fd = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.readNow()
        }
        source.setCancelHandler { [weak self] in
            guard let self = self else { return }
            close(self.fd)
        }
        self.source = source
        source.resume()
    }

    func send(_ data: Data) {
        queue.async {
            data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                var sent = 0
                while sent < raw.count {
                    let n = write(self.fd, base.advanced(by: sent), raw.count - sent)
                    if n <= 0 { self.closeStream(); return }
                    sent += n
                }
            }
        }
    }

    func closeStream() {
        queue.async {
            guard !self.closed else { return }
            self.closed = true
            self.source?.cancel()
            DispatchQueue.main.async { self.onClose?() }
        }
    }

    private func readNow() {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        let n = read(fd, &buffer, buffer.count)
        if n > 0 {
            let data = Data(buffer.prefix(n))
            onData?(data)
        } else if n == 0 {
            closeStream()
        }
    }
}
