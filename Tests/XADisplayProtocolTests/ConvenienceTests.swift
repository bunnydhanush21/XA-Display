import XCTest

@testable import XADisplayProtocol

final class ConvenienceTests: XCTestCase {
    func testSavedMacsResumeTheLastOne() {
        var directory = MacDirectory()
        directory.remember(SavedMac(id: "studio", name: "Studio", token: "AAAA-BBBB", lastUsed: 1))
        directory.remember(SavedMac(id: "kitchen", name: "Kitchen", token: "CCCC-DDDD", lastUsed: 2))
        XCTAssertEqual(directory.last()?.id, "kitchen")
        XCTAssertEqual(directory.sorted().map(\.id), ["kitchen", "studio"])
        directory.select("studio", now: 3)
        guard case .resume(let resumed) = LaunchRoute.decide(oneTap: true, directory: directory) else {
            return XCTFail("one-tap launch should resume the last Mac")
        }
        XCTAssertEqual(resumed.id, "studio")
        XCTAssertEqual(LaunchRoute.decide(oneTap: false, directory: directory), .picker)
        directory.remove("kitchen")
        XCTAssertEqual(LaunchRoute.decide(oneTap: false, directory: directory), .listen)
        XCTAssertFalse(WakeOnDemandPolicy.usesMagicPacket)
        XCTAssertEqual(WakeOnDemandPolicy.serviceType, "_xahost._tcp")
    }

    func testOldFeatureJSONGainsTheNewSwitches() throws {
        let old =
            #"{"requirePairing":true,"clipboardSync":false,"threeFingerShortcuts":true,"pinchMagnifier":true,"commandStrip":true,"windowSnapping":true,"audio":false,"savedPresets":true,"gestureTuning":{"slop":12,"doubleTapWindow":0.35,"longPressDuration":0.45,"scrollGain":1,"sidebarOnLeft":true},"autoConnectUSB":true,"touchscreenGestures":true,"wifiFallback":true,"trackpadMode":false,"scrollInertia":true,"showStats":true,"precisionMode":false,"inputRotation":0}"#
        let settings = try JSONDecoder().decode(XAFeatureSettings.self, from: Data(old.utf8))
        XCTAssertTrue(settings.oneTapReconnect)
        XCTAssertTrue(settings.rememberMacs)
        XCTAssertFalse(settings.mediaRemote)
        XCTAssertTrue(settings.requirePairing)
    }

    func testMediaCommandAndNowPlayingRoundTrip() throws {
        let command = XAInputMessage.media(XAMediaCommand(session: 4, seq: 9, action: .playPause, scrub: 0))
        XCTAssertEqual(try XAInputMessage.decode(try command.encode()), command)
        let seek = XAInputMessage.media(XAMediaCommand(session: 4, seq: 10, action: .seekForward, scrub: 0.25))
        XCTAssertEqual(try XAInputMessage.decode(try seek.encode()), seek)
        let info = XAInputMessage.nowPlaying(XANowPlaying(session: 4, appName: "Music", title: "", artist: "", position: XANowPlaying.unknownTime, duration: XANowPlaying.unknownTime))
        XCTAssertEqual(try XAInputMessage.decode(try info.encode()), info)
        XCTAssertFalse(XANowPlaying(session: 1, appName: "Music").hasPublicMetadata)
        XCTAssertEqual(MediaKeyMap.virtualKey(.playPause), 16)
        XCTAssertEqual(MediaKeyMap.virtualKey(.next), 17)
        XCTAssertEqual(MediaKeyMap.virtualKey(.previous), 18)
        XCTAssertEqual(MediaKeyMap.virtualKey(.volumeUp), 0)
        XCTAssertEqual(MediaKeyMap.data1(keyCode: 16, down: true), (16 << 16) | (0xA << 8))
        XCTAssertEqual(MediaKeyMap.data1(keyCode: 16, down: false), (16 << 16) | (0xB << 8))
        XCTAssertFalse(NowPlayingSource.usesPrivateMediaRemote)
    }

    func testMediaCommandsRequireTheSwitch() {
        var off = InputDispatcher(expectedToken: "ABCDEFGH", mediaEnabled: false)
        _ = off.handle(.hello(XAHello(protocolVersion: 1, token: "ABCDEFGH", deviceName: "iPad", deviceID: "1", flags: 0)), hostNowMs: 0)
        let blocked = off.handle(.media(XAMediaCommand(session: off.session, seq: 1, action: .next)), hostNowMs: 1)
        XCTAssertEqual(blocked, .drop)
        var on = InputDispatcher(expectedToken: "ABCDEFGH", mediaEnabled: true)
        _ = on.handle(.hello(XAHello(protocolVersion: 1, token: "ABCDEFGH", deviceName: "iPad", deviceID: "1", flags: 0)), hostNowMs: 0)
        let posted = on.handle(.media(XAMediaCommand(session: on.session, seq: 1, action: .volumeDown, scrub: 0)), hostNowMs: 1)
        XCTAssertEqual(posted, .post([.media(.volumeDown, scrub: 0)]))
    }
}
