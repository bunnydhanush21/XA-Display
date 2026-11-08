@preconcurrency import Foundation
@preconcurrency import ServiceManagement
import XADisplayProtocol
@preconcurrency import os

enum XALog {
    private static let subsystem = "com.bunnydhanush.xadisplay"
    static let net = Logger(subsystem: subsystem, category: "net")
    static let video = Logger(subsystem: subsystem, category: "video")
    static let input = Logger(subsystem: subsystem, category: "input")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let ui = Logger(subsystem: subsystem, category: "ui")

    static func write(_ logger: Logger, _ line: String) {
        event(logger, "message", ["text": line])
    }

    static func event(_ logger: Logger, _ name: String, _ fields: [String: String]) {
        let body = ([name] + fields.keys.sorted().map { "\($0)=\(fields[$0] ?? "")" }).joined(separator: " ")
        let clean = LogRing.redact(body)
        logger.info("\(clean, privacy: .public)")
    }
}

enum LoginItem {
    static func setEnabled(_ enabled: Bool) {
        if enabled {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }
}
