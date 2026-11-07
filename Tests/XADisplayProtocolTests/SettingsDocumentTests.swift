import XCTest

@testable import XADisplayProtocol

final class SettingsDocumentTests: XCTestCase {
    func testDefaultsAndCatalogCoverBothApps() {
        let document = XASettingsDocument.defaults
        XCTAssertEqual(document.version, 1)
        XCTAssertFalse(document.features.clipboardSync)
        XCTAssertFalse(document.features.audio)
        XCTAssertTrue(document.features.batteryTelemetry)
        XCTAssertFalse(document.features.chargeLimit)
        XCTAssertEqual(document.charge.stopAtPercent, 80)
        XCTAssertEqual(document.charge.resumeAtPercent, 75)
        XCTAssertEqual(document.preset, "balanced")
        XCTAssertEqual(document.value(for: "touch.mode"), .choice("direct"))
        XCTAssertTrue(SettingsCatalog.padSections.contains("Battery care"))
        XCTAssertTrue(SettingsCatalog.hostSections.contains("Permissions"))
        let padIDs = SettingsCatalog.padSections.flatMap { SettingsCatalog.rows(in: $0, host: false).map(\.id) }
        XCTAssertTrue(padIDs.contains("connection.usb"))
        XCTAssertTrue(padIDs.contains("about.reset"))
        XCTAssertTrue(padIDs.contains("battery.limit"))
        XCTAssertFalse(SettingsCatalog.rows(in: "Permissions", host: false).contains { $0.id == "permissions.screen" })
        XCTAssertTrue(SettingsCatalog.rows(in: "Audio", host: true).contains { $0.id == "audio.mode" })
    }

    func testRoundTripAndLegacyMigration() throws {
        var document = XASettingsDocument.defaults
        document.set(.bool(true), for: "clipboard.sync")
        document.set(.number(0.4), for: "audio.volume")
        document.set(.choice("safe"), for: "display.preset")
        document.set(.number(0.9), for: "touch.hold")
        let decoded = XASettingsDocument.decode(document.encode())
        XCTAssertEqual(decoded.features.clipboardSync, true)
        XCTAssertEqual(decoded.audioVolume, 0.4, accuracy: 0.001)
        XCTAssertEqual(decoded.preset, "safe")
        XCTAssertEqual(decoded.features.gestureTuning.longPressDuration, 0.9, accuracy: 0.001)
        let legacy = try JSONEncoder().encode(XAFeatureSettings(clipboardSync: true, audio: true))
        let migrated = XASettingsDocument.migrate(featuresJSON: legacy)
        XCTAssertTrue(migrated.features.clipboardSync)
        XCTAssertTrue(migrated.features.audio)
        XCTAssertTrue(migrated.features.batteryTelemetry)
        XCTAssertEqual(migrated.rightClick, "both")
        let fromLegacyBlob = XASettingsDocument.decode(legacy)
        XCTAssertTrue(fromLegacyBlob.features.clipboardSync)
        XCTAssertEqual(fromLegacyBlob.version, 1)
    }

    func testSyncDoesNotClobberLocalTouchSettings() {
        var local = XASettingsDocument.defaults
        local.set(.number(32), for: "touch.threshold")
        local.set(.bool(false), for: "touch.pinch")
        var remote = XASettingsDocument.defaults
        remote.set(.bool(true), for: "clipboard.sync")
        remote.set(.choice("native"), for: "display.preset")
        remote.set(.number(0.2), for: "audio.volume")
        let merged = SettingsSync.apply(SettingsSync.encode(remote), to: local)
        XCTAssertTrue(merged.features.clipboardSync)
        XCTAssertEqual(merged.preset, "native")
        XCTAssertEqual(merged.audioVolume, 0.2, accuracy: 0.001)
        XCTAssertEqual(merged.features.gestureTuning.slop, 32, accuracy: 0.001)
        XCTAssertFalse(merged.features.pinchMagnifier)
        var reset = merged
        reset.reset()
        XCTAssertEqual(reset, XASettingsDocument.defaults)
    }
}
