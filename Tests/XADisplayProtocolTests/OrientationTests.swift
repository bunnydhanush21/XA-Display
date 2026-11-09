import XCTest

@testable import XADisplayProtocol

final class OrientationTests: XCTestCase {
    func testPortraitModesAndFallback() {
        XCTAssertEqual(PortraitModes.size(preset: .balanced)?.width, 1080)
        XCTAssertEqual(PortraitModes.size(preset: .balanced)?.height, 1440)
        XCTAssertEqual(PortraitModes.size(preset: .safe)?.width, 768)
        XCTAssertEqual(PortraitModes.size(preset: .native)?.height, 2048)
        let landscape = PortraitModes.landscape(preset: .balanced)
        let swap = OrientationPolicy.action(
            currentPortrait: false, requested: "portrait", follow: true, lock: "none", mode: "resolution",
            portraitSize: PortraitModes.size(preset: .balanced), landscapeSize: landscape
        )
        XCTAssertEqual(swap, .reconfigure(width: 1080, height: 1440))
        let blocked = OrientationPolicy.action(
            currentPortrait: false, requested: "portrait", follow: true, lock: "none", mode: "resolution",
            portraitSize: nil, landscapeSize: landscape
        )
        XCTAssertEqual(blocked, .letterbox)
        XCTAssertEqual(
            OrientationPolicy.action(currentPortrait: true, requested: "landscape", follow: true, lock: "none", mode: "resolution", portraitSize: nil, landscapeSize: landscape),
            .reconfigure(width: 1440, height: 1080)
        )
        XCTAssertEqual(
            OrientationPolicy.action(
                currentPortrait: false, requested: "portrait", follow: false, lock: "none", mode: "resolution", portraitSize: PortraitModes.size(preset: .balanced), landscapeSize: landscape),
            .ignore
        )
        XCTAssertEqual(
            OrientationPolicy.action(
                currentPortrait: false, requested: "portrait", follow: true, lock: "landscape", mode: "resolution", portraitSize: PortraitModes.size(preset: .balanced), landscapeSize: landscape),
            .ignore
        )
        XCTAssertEqual(
            OrientationPolicy.action(currentPortrait: false, requested: "portrait", follow: true, lock: "none", mode: "stream", portraitSize: nil, landscapeSize: landscape),
            .rotateStream
        )
    }

    func testDebounceAndMapping() {
        var debounce = OrientationDebounce()
        debounce.note("portrait", now: 1)
        XCTAssertNil(debounce.due(now: 1.2))
        XCTAssertEqual(debounce.due(now: 1.3), "portrait")
        XCTAssertNil(debounce.due(now: 2))
        debounce.note("landscape", now: 2)
        debounce.note("portrait", now: 2.1)
        XCTAssertNil(debounce.due(now: 2.4))
        debounce.note("landscape", now: 3)
        XCTAssertNil(debounce.due(now: 3.2))
        XCTAssertEqual(debounce.due(now: 3.3), "landscape")
        debounce.note("portrait", now: 4)
        XCTAssertEqual(debounce.due(now: 4.3), "portrait")
        XCTAssertEqual(OrientationMapping.rotation(mode: "stream", devicePortrait: true), .clockwise90)
        XCTAssertEqual(OrientationMapping.rotation(mode: "resolution", devicePortrait: true), .identity)
        let landscape = XASize(width: 1440, height: 1080)
        let portraitView = XASize(width: 768, height: 1024)
        let topLeft = CoordinateMapper.normalize(
            MapRequest(
                point: XAPoint(x: 0, y: 0), pointSpace: .viewPoints, viewSizePoints: portraitView,
                pixelsPerPoint: 2, videoPixelSize: landscape, rotation: .clockwise90
            ))
        XCTAssertEqual(topLeft?.x ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(topLeft?.y ?? -1, 1, accuracy: 0.001)
        let bottomRight = CoordinateMapper.normalize(
            MapRequest(
                point: XAPoint(x: 768, y: 1024), pointSpace: .viewPoints, viewSizePoints: portraitView,
                pixelsPerPoint: 2, videoPixelSize: landscape, rotation: .clockwise90
            ))
        XCTAssertEqual(bottomRight?.x ?? -1, 1, accuracy: 0.001)
        XCTAssertEqual(bottomRight?.y ?? -1, 0, accuracy: 0.001)
        XCTAssertNil(
            CoordinateMapper.normalize(
                MapRequest(
                    point: .zero, pointSpace: .viewPoints, viewSizePoints: XASize(width: 100, height: 200),
                    pixelsPerPoint: 1, videoPixelSize: landscape, rotation: .identity
                )))
        let matched = CoordinateMapper.normalize(
            MapRequest(
                point: XAPoint(x: 540, y: 720), pointSpace: .viewPoints, viewSizePoints: XASize(width: 1080, height: 1440),
                pixelsPerPoint: 1, videoPixelSize: XASize(width: 1080, height: 1440), rotation: .identity
            ))
        XCTAssertEqual(matched?.x ?? -1, 0.5, accuracy: 0.001)
        XCTAssertEqual(matched?.y ?? -1, 0.5, accuracy: 0.001)
        XCTAssertEqual(OrientationMapping.scrollDelta(XAPoint(x: 0, y: 10), rotation: .clockwise90), XAPoint(x: 10, y: 0))
        let message = VideoControlMessage.xaOrient(orientation: "portrait", mode: "resolution", letterbox: false)
        XCTAssertEqual(VideoControlMessage.parse(message.jsonData() ?? Data()), message)
        let fallback = VideoControlMessage.xaOrient(orientation: "portrait", mode: "resolution", letterbox: true)
        XCTAssertEqual(VideoControlMessage.parse(fallback.jsonData() ?? Data()), fallback)
        var document = XASettingsDocument.defaults
        XCTAssertTrue(document.features.followRotation)
        XCTAssertEqual(document.features.orientationLock, "none")
        XCTAssertEqual(document.features.rotationMode, "resolution")
        document.set(.bool(false), for: "display.follow")
        document.set(.choice("portrait"), for: "display.lock")
        document.set(.choice("stream"), for: "display.mode")
        let decoded = XASettingsDocument.decode(document.encode())
        XCTAssertFalse(decoded.features.followRotation)
        XCTAssertEqual(decoded.features.orientationLock, "portrait")
        let merged = SettingsSync.apply(SettingsSync.encode(document), to: XASettingsDocument.defaults)
        XCTAssertEqual(merged.features.rotationMode, "stream")
        XCTAssertFalse(merged.features.followRotation)
    }
}
