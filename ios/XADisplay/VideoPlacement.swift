import UIKit

enum VideoPlacement {
    struct Frame {
        var bounds: CGRect
        var center: CGPoint
        var transform: CGAffineTransform
    }

    /// Landscape framebuffer drawn into a portrait view. Bounds stay in framebuffer space so touches map without a second rotation.
    static func frame(host: CGRect, rotateClockwise: Bool) -> Frame {
        if rotateClockwise {
            return Frame(
                bounds: CGRect(x: 0, y: 0, width: host.height, height: host.width),
                center: CGPoint(x: host.midX, y: host.midY),
                transform: CGAffineTransform(rotationAngle: -.pi / 2)
            )
        }
        return Frame(
            bounds: host,
            center: CGPoint(x: host.midX, y: host.midY),
            transform: .identity
        )
    }
}
