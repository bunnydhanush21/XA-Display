import Foundation

/// KeyShortcut.
public struct KeyShortcut: Equatable {
    public var input: String
    public var modifiers: XAModifierMask
    public init(input: String, modifiers: XAModifierMask) {
        self.input = input
        self.modifiers = modifiers
    }

    public func intents() -> [InputIntent] {
        guard let code = Self.keyCode(for: input) else { return [] }
        return [
            .key(phase: .down, keyCode: code, modifiers: modifiers, text: ""),
            .key(phase: .up, keyCode: code, modifiers: modifiers, text: "")
        ]
    }

    public static func keyCode(for input: String) -> UInt16? {
        switch input {
        case "\u{1b}": return MacKeyCode.escape
        case "UIKeyInputUpArrow": return MacKeyCode.upArrow
        case "UIKeyInputDownArrow": return MacKeyCode.downArrow
        case "UIKeyInputLeftArrow": return MacKeyCode.leftArrow
        case "UIKeyInputRightArrow": return MacKeyCode.rightArrow
        case "\t": return MacKeyCode.tab
        case "\r", "\n": return MacKeyCode.return
        case "=": return 24
        case "-": return 27
        case "UIKeyInputF4": return 118
        default:
            guard input.count == 1, let character = input.first else { return nil }
            return MacKeyCode.letter(character) ?? MacKeyCode.digit(character)
        }
    }
}

/// TextEntry.
public enum TextEntry {
    public static func insert(_ text: String) -> [InputIntent] {
        text.map { character in
            let code = MacKeyCode.letter(character) ?? MacKeyCode.digit(character) ?? 0
            return .key(phase: .typed, keyCode: code, modifiers: [], text: String(character))
        }
    }
    public static func delete() -> [InputIntent] {
        [
            .key(phase: .down, keyCode: MacKeyCode.delete, modifiers: [], text: ""),
            .key(phase: .up, keyCode: MacKeyCode.delete, modifiers: [], text: "")
        ]
    }
}
