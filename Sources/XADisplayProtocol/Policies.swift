import Foundation

/// AudioPolicy.
public enum AudioPolicy {
    public static func accept(enabled: Bool, armed: Bool, byteCount: Int, channels: Int, codec: XAAudioCodec = .pcm) -> Bool {
        guard enabled, armed, channels >= 1, channels <= 2, byteCount > 0, byteCount <= XAAudio.maxBytes else { return false }
        if codec == .pcm {
            return byteCount % (2 * channels) == 0
        }
        return true
    }
}

/// ClipboardPolicy.
public enum ClipboardPolicy {
    public static func accept(enabled: Bool, armed: Bool, utf8Count: Int) -> Bool {
        enabled && armed && utf8Count <= XAClipboard.maxBytes
    }
}
