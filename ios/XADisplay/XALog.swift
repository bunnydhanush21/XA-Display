import Foundation
import os

enum XALog {
    private static let subsystem = "com.bunnydhanush.xadisplay"
    static let net = OSLog(subsystem: subsystem, category: "net")
    static let video = OSLog(subsystem: subsystem, category: "video")
    static let input = OSLog(subsystem: subsystem, category: "input")
    static let audio = OSLog(subsystem: subsystem, category: "audio")
    static let ui = OSLog(subsystem: subsystem, category: "ui")

    static func write(_ log: OSLog, _ line: String) {
        os_log("%{public}@", log: log, type: .info, line)
    }
}

enum ReceiverQueues {
    static let network = DispatchQueue(label: "xa.ipad.network")
    static let decode = DispatchQueue(label: "xa.ipad.decode")
    static let input = DispatchQueue(label: "xa.ipad.input")
}
