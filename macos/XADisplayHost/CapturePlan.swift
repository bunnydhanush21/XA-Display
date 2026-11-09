@preconcurrency import CoreMedia
@preconcurrency import CoreVideo
@preconcurrency import Foundation
@preconcurrency import ScreenCaptureKit

/// ScreenCaptureKit settings for a stream that is already the target size. Idle frames are duplicates and are not encoded.
enum CapturePlan {
    static let queueDepth = 2
    static let pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange

    static func apply(to config: SCStreamConfiguration, width: Int, height: Int, fps: Int) {
        config.width = width
        config.height = height
        config.pixelFormat = pixelFormat
        config.showsCursor = false
        config.queueDepth = queueDepth
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(fps, 1)))
        config.scalesToFit = false
        config.capturesAudio = false
    }

    static func shouldEncode(_ status: SCFrameStatus?) -> Bool {
        guard let status else { return true }
        switch status {
        case .idle, .blank, .suspended, .stopped:
            return false
        case .complete, .started:
            return true
        @unknown default:
            return true
        }
    }
}
