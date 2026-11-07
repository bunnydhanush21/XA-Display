import CoreGraphics
import Foundation
import XADisplayProtocol

final class EventPoster {
    func post(_ event: PostedEvent) {
        switch event {
        case .mouse(let phase, let button, let global):
            let type: CGEventType
            let cgButton: CGMouseButton
            switch button {
            case .left: cgButton = .left
            case .right: cgButton = .right
            case .middle: cgButton = .center
            }
            switch phase {
            case .move: type = .mouseMoved
            case .down: type = button == .left ? .leftMouseDown : (button == .right ? .rightMouseDown : .otherMouseDown)
            case .up: type = button == .left ? .leftMouseUp : (button == .right ? .rightMouseUp : .otherMouseUp)
            case .drag: type = button == .left ? .leftMouseDragged : (button == .right ? .rightMouseDragged : .otherMouseDragged)
            }
            let cg = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: global.x, y: global.y), mouseButton: cgButton)
            cg?.post(tap: .cghidEventTap)
        case .scroll(let dx, let dy):
            let wheel = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: ScrollWheelSign.wheel1(contentDownPixels: dy),
                wheel2: ScrollWheelSign.wheel2(contentRightPixels: dx),
                wheel3: 0
            )
            wheel?.post(tap: .cghidEventTap)
        case .key(let phase, let code, let modifiers, let text):
            let down = phase != .up
            let cg = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: down)
            cg?.flags = cgFlags(modifiers)
            if !text.isEmpty, let cg = cg {
                let units = Array(text.utf16)
                units.withUnsafeBufferPointer { buffer in
                    if let base = buffer.baseAddress {
                        cg.keyboardSetUnicodeString(stringLength: units.count, unicodeString: base)
                    }
                }
            }
            cg?.post(tap: .cghidEventTap)
            if phase == .typed {
                let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: false)
                up?.flags = cgFlags(modifiers)
                up?.post(tap: .cghidEventTap)
            }
        case .modifier(let bit, let down):
            let code: CGKeyCode
            switch bit {
            case .shift: code = CGKeyCode(MacKeyCode.shift)
            case .control: code = CGKeyCode(MacKeyCode.control)
            case .option: code = CGKeyCode(MacKeyCode.option)
            case .command: code = CGKeyCode(MacKeyCode.command)
            default: return
            }
            let cg = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            cg?.post(tap: .cghidEventTap)
        case .clipboard, .window, .chrome, .media:
            break
        }
    }

    private func cgFlags(_ mask: XAModifierMask) -> CGEventFlags {
        var flags = CGEventFlags()
        if mask.contains(.shift) { flags.insert(.maskShift) }
        if mask.contains(.control) { flags.insert(.maskControl) }
        if mask.contains(.option) { flags.insert(.maskAlternate) }
        if mask.contains(.command) { flags.insert(.maskCommand) }
        return flags
    }
}
