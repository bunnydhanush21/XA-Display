import XCTest
@testable import XADisplayProtocol

final class AudioTests: XCTestCase {
    func testAudioPacketRoundTripCarriesCodecAndTimestamp() throws {
        let packet = XAInputMessage.audio(XAAudio(
            session: 9, sampleRate: 48_000, channels: 2,
            pcm: Data([1, 2, 3, 4, 5, 6]), codec: .aac, hostTimeMs: 1_700_000_123.5
        ))
        let decoded = try XAInputMessage.decode(try packet.encode())
        XCTAssertEqual(decoded, packet)
        let pcm = XAInputMessage.audio(XAAudio(session: 1, sampleRate: 48_000, channels: 2, pcm: Data([0, 1, 2, 3])))
        XCTAssertEqual(try XAInputMessage.decode(try pcm.encode()), pcm)
    }

    func testAudioPolicyRejectsUnalignedPCMAndOversizedAAC() {
        XCTAssertFalse(AudioPolicy.accept(enabled: true, armed: true, byteCount: 3, channels: 2, codec: .pcm))
        XCTAssertTrue(AudioPolicy.accept(enabled: true, armed: true, byteCount: 4, channels: 2, codec: .pcm))
        XCTAssertTrue(AudioPolicy.accept(enabled: true, armed: true, byteCount: 17, channels: 2, codec: .aac))
        XCTAssertFalse(AudioPolicy.accept(enabled: true, armed: true, byteCount: XAAudio.maxBytes + 1, channels: 2, codec: .aac))
        XCTAssertFalse(AudioPolicy.accept(enabled: false, armed: true, byteCount: 4, channels: 2))
        XCTAssertEqual(XAAudio.aacPacketMilliseconds, 21)
    }

    func testClockOffsetAndScheduledPlay() {
        let offset = AudioSyncMath.clockOffsetClientMinusHost(clientSendMs: 1000, hostMs: 5000, clientRecvMs: 1040)
        XCTAssertEqual(offset ?? -1, 1000 + 20 - 5000, accuracy: 0.001)
        let play = AudioSyncMath.scheduledPlayMs(hostCaptureMs: 5000, offsetClientMinusHost: offset ?? 0, jitterMs: 60)
        XCTAssertEqual(play, 5000 + (1020 - 5000) + 60, accuracy: 0.001)
        XCTAssertNil(AudioSyncMath.clockOffsetClientMinusHost(clientSendMs: 50, hostMs: 10, clientRecvMs: 40))
        XCTAssertNil(AudioSyncMath.clockOffsetClientMinusHost(clientSendMs: 0, hostMs: 0, clientRecvMs: 20_000))
    }

    func testJitterSchedulePlaysHoldsAndDrops() {
        let scheduled = 1_000.0
        XCTAssertEqual(AudioSyncMath.schedule(nowClientMs: 900, scheduledMs: scheduled, queued: 1), .hold)
        XCTAssertEqual(AudioSyncMath.schedule(nowClientMs: 1000, scheduledMs: scheduled, queued: 1), .play)
        XCTAssertEqual(AudioSyncMath.schedule(nowClientMs: 1130, scheduledMs: scheduled, queued: 1), .play)
        XCTAssertEqual(AudioSyncMath.schedule(nowClientMs: 1200, scheduledMs: scheduled, queued: 1), .dropLate)
        XCTAssertEqual(AudioSyncMath.schedule(nowClientMs: 1000, scheduledMs: scheduled, queued: 7), .dropOverflow)
    }

    func testJitterQueueDropsLateAndPlaysInOrder() {
        var queue = AudioJitterQueue()
        queue.offsetClientMinusHost = 0
        XCTAssertEqual(queue.push(hostMs: 200, payload: Data([2])), .hold)
        XCTAssertEqual(queue.push(hostMs: 100, payload: Data([1])), .hold)
        XCTAssertNil(queue.popReady(nowClientMs: 100))
        let first = queue.popReady(nowClientMs: 160)
        XCTAssertEqual(first?.payload, Data([1]))
        XCTAssertNil(queue.popReady(nowClientMs: 420))
        XCTAssertTrue(queue.slots.isEmpty)
    }

    func testRoutePlannerSelectsApps() {
        XCTAssertEqual(AudioRoutePlanner.choice(mode: .all, selectedBundleIDs: ["com.a"], bundlesOnDisplay: ["com.b"]), .allApplications)
        XCTAssertEqual(
            AudioRoutePlanner.choice(mode: .selected, selectedBundleIDs: ["com.b", "com.a", "com.a"], bundlesOnDisplay: []),
            .includingBundles(["com.a", "com.b"])
        )
        let display = XARect(x: 0, y: 0, width: 100, height: 100)
        let ids = AudioRoutePlanner.bundleIDsOnDisplay(
            windows: [(pid: 1, bounds: XARect(x: 10, y: 10, width: 20, height: 20)), (pid: 2, bounds: XARect(x: 400, y: 10, width: 20, height: 20))],
            display: display,
            bundlesByPID: [1: "com.on", 2: "com.off"]
        )
        XCTAssertEqual(ids, ["com.on"])
        XCTAssertEqual(AudioRoutePlanner.choice(mode: .displayApps, selectedBundleIDs: [], bundlesOnDisplay: ids), .includingBundles(["com.on"]))
    }

    func testAACPacketFramingRejectsOversize() {
        let packed = AACPacket.pack(cookie: Data([9, 8]), frame: Data([1, 2, 3]))
        XCTAssertEqual(packed?.first, 0)
        XCTAssertEqual(AACPacket.unpack(packed ?? Data())?.frame, Data([1, 2, 3]))
        XCTAssertNil(AACPacket.pack(cookie: Data(repeating: 1, count: 600), frame: Data([1])))
        XCTAssertNil(AACPacket.unpack(Data([0, 5, 1])))
    }

    func testVolumeScalesLittleEndianPCM() {
        var loud = Data()
        let sample: Int16 = 1000
        let bits = UInt16(bitPattern: sample)
        loud.append(UInt8(bits & 0xff))
        loud.append(UInt8(bits >> 8))
        XCTAssertEqual(AudioVolume.scalePCM16(pcm: loud, volume: 1), loud)
        let quiet = AudioVolume.scalePCM16(pcm: loud, volume: 0.5)
        XCTAssertEqual(quiet, Data([0xf4, 0x01]))
        let silent = AudioVolume.scalePCM16(pcm: loud, volume: 0)
        XCTAssertEqual(silent, Data([0, 0]))
    }
}
