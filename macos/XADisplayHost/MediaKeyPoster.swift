@preconcurrency import AppKit
@preconcurrency import Foundation
import XADisplayProtocol

enum MediaKeyPoster {
    static func post(_ action: MediaAction) {
        let key = MediaKeyMap.virtualKey(action)
        post(keyCode: key, down: true)
        post(keyCode: key, down: false)
    }

    private static func post(keyCode: Int32, down: Bool) {
        let data1 = MediaKeyMap.data1(keyCode: keyCode, down: down)
        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xA00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: Int16(MediaKeyMap.systemDefinedSubtype),
            data1: Int(data1),
            data2: -1
        )
        event?.cgEvent?.post(tap: .cghidEventTap)
    }
}
