import XCTest

@testable import XADisplayProtocol

final class BatteryCareTests: XCTestCase {
    func testMissingFieldsStayUnavailable() {
        let sample = BatteryReading.sample(raw: RawBatteryProperties(), deviceLevel: nil, deviceCharging: nil, cycleCount: nil)
        let text = BatteryDisplay.menuText(sample)
        XCTAssertFalse(text.contains("Level: 0%"))
        XCTAssertTrue(text.contains("Level: unavailable"))
        XCTAssertTrue(text.contains("Cycles: unavailable"))
        XCTAssertTrue(text.contains("Health: unavailable"))
        XCTAssertTrue(text.contains("Temperature: unavailable"))
        XCTAssertTrue(text.contains("Current: unavailable"))
        XCTAssertTrue(text.contains("Voltage: unavailable"))
        XCTAssertNil(sample.amperageMilliAmps)
        XCTAssertNil(sample.voltageMilliVolts)
    }

    func testTemperatureAndHealthConversion() {
        XCTAssertEqual(BatteryTemperature.celsius(raw: 30) ?? -999, 30, accuracy: 0.01)
        XCTAssertEqual(BatteryTemperature.celsius(raw: 3_050) ?? -999, 30.5, accuracy: 0.01)
        XCTAssertEqual(BatteryTemperature.celsius(raw: 305) ?? -999, 30.5, accuracy: 0.01)
        XCTAssertNil(BatteryTemperature.celsius(raw: 27315))
        XCTAssertNil(BatteryTemperature.celsius(raw: .nan))
        XCTAssertEqual(BatteryHealth.fraction(nominal: 900, appleRawMax: 100, design: 1_000) ?? -1, 0.9, accuracy: 0.001)
        XCTAssertEqual(BatteryHealth.fraction(nominal: nil, appleRawMax: 800, design: 1_000) ?? -1, 0.8, accuracy: 0.001)
        XCTAssertNil(BatteryHealth.fraction(nominal: 10, appleRawMax: 10, design: 1_000))
        XCTAssertNil(BatteryHealth.fraction(nominal: 900, appleRawMax: nil, design: 0))
        let raw = RawBatteryProperties(
            currentCapacity: 80, maxCapacity: 100, nominalChargeCapacity: 900, designCapacity: 1_000, temperatureRaw: 3_200,
            isCharging: true, externalConnected: true, amperageMilliAmps: -400, voltageMilliVolts: 4_200
        )
        let sample = BatteryReading.sample(raw: raw, deviceLevel: 0.1, deviceCharging: false, cycleCount: 120)
        XCTAssertEqual(sample.levelPercent ?? 0, 80, accuracy: 0.1)
        XCTAssertEqual(sample.temperatureC ?? 0, 32, accuracy: 0.1)
        XCTAssertEqual(sample.healthFraction ?? 0, 0.9, accuracy: 0.01)
        XCTAssertEqual(sample.cycleCount, 120)
        XCTAssertEqual(sample.amperageMilliAmps, -400)
        XCTAssertEqual(sample.voltageMilliVolts, 4_200)
        XCTAssertEqual(sample.source, "registry")
        let fallback = BatteryReading.sample(raw: RawBatteryProperties(), deviceLevel: 0.42, deviceCharging: false, cycleCount: nil)
        XCTAssertEqual(fallback.levelPercent ?? 0, 42, accuracy: 0.1)
        XCTAssertEqual(fallback.source, "uidevice")
        XCTAssertFalse(fallback.isCharging ?? true)
    }

    func testHysteresisStopsAndResumes() {
        var session = ChargeSession()
        let config = ChargeLimitConfig(stopAtPercent: 80, resumeAtPercent: 75)
        XCTAssertEqual(session.step(enabled: true, killSwitch: false, levelPercent: 79, watchdog: .none, config: config), .none)
        XCTAssertEqual(session.step(enabled: true, killSwitch: false, levelPercent: 80, watchdog: .none, config: config), .stopCharging)
        XCTAssertEqual(session.step(enabled: true, killSwitch: false, levelPercent: 78, watchdog: .none, config: config), .none)
        XCTAssertTrue(session.paused)
        XCTAssertEqual(session.step(enabled: true, killSwitch: false, levelPercent: 75, watchdog: .none, config: config), .resumeCharging)
        XCTAssertFalse(session.paused)
        XCTAssertEqual(session.step(enabled: false, killSwitch: false, levelPercent: 90, watchdog: .none, config: config), .none)
    }

    func testWatchdogRestoresCharging() {
        var session = ChargeSession()
        let config = ChargeLimitConfig()
        XCTAssertEqual(session.step(enabled: true, killSwitch: false, levelPercent: 90, watchdog: .none, config: config), .stopCharging)
        let hot = ChargeWatchdog.decide(WatchdogInput(levelPercent: 90, chargingPaused: true, temperatureC: 41))
        XCTAssertEqual(hot, .temperature)
        XCTAssertEqual(session.step(enabled: true, killSwitch: false, levelPercent: 90, watchdog: hot, config: config), .resumeCharging)
        XCTAssertEqual(ChargeWatchdog.decide(WatchdogInput(telemetryAgeSeconds: 31, levelPercent: 50)), .staleTelemetry)
        XCTAssertEqual(ChargeWatchdog.decide(WatchdogInput(telemetryAgeSeconds: 1, readFailed: true)), .readError)
        XCTAssertEqual(ChargeWatchdog.decide(WatchdogInput(telemetryAgeSeconds: 1, levelPercent: 19)), .lowBattery)
        XCTAssertEqual(
            ChargeWatchdog.decide(
                WatchdogInput(
                    telemetryAgeSeconds: 1, levelPercent: 76, previousLevelPercent: 80, secondsSincePrevious: 40, chargingPaused: true, externalConnected: true
                )), .unexpectedDrain)
        XCTAssertEqual(ChargeWatchdog.decide(WatchdogInput(telemetryAgeSeconds: 1, levelPercent: 76, previousLevelPercent: 80, chargingPaused: true, externalConnected: false)), .none)
        XCTAssertEqual(session.step(enabled: true, killSwitch: true, levelPercent: 90, watchdog: .none, config: config), .none)
        _ = session.step(enabled: true, killSwitch: false, levelPercent: 90, watchdog: .none, config: config)
        XCTAssertEqual(session.step(enabled: true, killSwitch: true, levelPercent: 90, watchdog: .none, config: config), .resumeCharging)
    }

    func testChargeCommandsRejectPrivateFallbacks() {
        XCTAssertEqual(BatteryCareOp.parse("status"), .status)
        XCTAssertEqual(BatteryCareOp.parse("charge-off"), .setCharging(false))
        XCTAssertEqual(BatteryCareOp.parse("charge-on"), .setCharging(true))
        XCTAssertEqual(BatteryCareOp.parse("restore"), .restore)
        XCTAssertNil(BatteryCareOp.parse("DisableInflow"))
        XCTAssertNil(BatteryCareOp.parse("ExternalConnected"))
        XCTAssertNil(BatteryCareOp.parse("charge-off; DisableInflow"))
        XCTAssertFalse(HeatResponse.touchesThermalControls)
        XCTAssertEqual(HeatResponse.bitrateFactor(temperatureC: 36), 0.7, accuracy: 0.01)
        XCTAssertEqual(HeatResponse.bitrateFactor(temperatureC: nil), 1, accuracy: 0.01)
        let limits = ChargeLimitConfig(stopAtPercent: 10, resumeAtPercent: 5).validated()
        XCTAssertGreaterThanOrEqual(limits.resumeAtPercent, 21)
        XCTAssertGreaterThanOrEqual(limits.stopAtPercent, limits.resumeAtPercent + 5)
        let wire = VideoControlMessage.xaBattery(text: BatteryDisplay.menuText(BatterySample(levelPercent: 81, source: "registry")), heat: true)
        XCTAssertEqual(VideoControlMessage.parse(wire.jsonData() ?? Data()), wire)
    }
}
