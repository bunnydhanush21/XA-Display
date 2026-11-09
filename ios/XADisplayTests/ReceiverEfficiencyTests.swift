import AVFoundation
import CoreMedia
import UIKit
import XADisplayProtocol
import XCTest

@testable import XADisplay

final class ReceiverEfficiencyTests: XCTestCase {
    func testFramePoolWritesEachNALOnce() {
        let pool = FrameMemoryPool()
        let nalu = Data([0x65, 0x11])
        guard let block = pool.block(nalus: [nalu]) else { return XCTFail("block") }
        var bytes = [UInt8](repeating: 0, count: 6)
        XCTAssertEqual(CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: 6, destination: &bytes), noErr)
        XCTAssertEqual(bytes, [0, 0, 0, 2, 0x65, 0x11])
        let again = pool.block(nalus: [Data([0x41, 0x02, 0x03])])
        XCTAssertNotNil(again)
    }

    func testHandleScansAnnexBOnTheVideoQueue() {
        let receiver = VideoReceiver(displayLayer: AVSampleBufferDisplayLayer())
        let payload = AnnexB.encode(timingJSON: nil, nalus: [Data([0x67, 0x42, 0x00]), Data([0x68, 0xCE]), Data([0x65, 0x88])])
        receiver.queue.sync {
            receiver.handle(payload)
            XCTAssertEqual(receiver.sps?.first, 0x67)
            XCTAssertEqual(receiver.pps?.first, 0x68)
        }
    }
}
