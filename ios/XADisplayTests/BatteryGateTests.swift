import UIKit
import XADisplayProtocol
import XCTest

@testable import XADisplay

final class BatteryGateTests: XCTestCase {
    func testTickSkipsIOKitUnlessTelemetryOrChargeLimitIsOn() {
        let loop = BatteryCareLoop()
        var reads = 0
        loop.readRegistry = {
            reads += 1
            return nil
        }
        let idle = loop.tick(enabledTelemetry: false, chargeLimit: false, config: ChargeLimitConfig())
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(idle.text, "")

        _ = loop.tick(enabledTelemetry: true, chargeLimit: false, config: ChargeLimitConfig())
        XCTAssertEqual(reads, 1)
        _ = loop.tick(enabledTelemetry: false, chargeLimit: true, config: ChargeLimitConfig())
        XCTAssertEqual(reads, 2)
    }

    func testNilRegistryFallsBackWithoutCrashing() {
        let loop = BatteryCareLoop()
        loop.readRegistry = { nil }
        UIDevice.current.isBatteryMonitoringEnabled = true
        let result = loop.tick(enabledTelemetry: true, chargeLimit: false, config: ChargeLimitConfig())
        if UIDevice.current.batteryLevel >= 0 {
            XCTAssertTrue(result.text.contains("Source: uidevice"))
        } else {
            XCTAssertTrue(result.text.contains("Source: none"))
            XCTAssertTrue(result.text.contains("Level: unavailable"))
        }
        XCTAssertFalse(result.heat)
    }
}
