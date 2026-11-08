import Darwin
import Foundation
import UIKit
import XADisplayProtocol

enum BatteryRegistry {
    static func read() -> RawBatteryProperties? {
        guard let service = matchingService("AppleARMPMUCharger") ?? matchingService("IOPMPowerSource") ?? matchingService("AppleSmartBattery") else {
            return nil
        }
        defer { release(service) }
        guard let properties = copyProperties(service) else { return nil }
        return parse(properties)
    }

    private static func parse(_ properties: [String: Any]) -> RawBatteryProperties {
        func number(_ key: String) -> Double? {
            if let value = properties[key] as? NSNumber { return value.doubleValue }
            if let value = properties[key] as? Double { return value }
            if let value = properties[key] as? Int { return Double(value) }
            return nil
        }
        func flag(_ key: String) -> Bool? {
            guard let value = number(key) else { return nil }
            return value != 0
        }
        return RawBatteryProperties(
            currentCapacity: number("CurrentCapacity"),
            maxCapacity: number("MaxCapacity"),
            nominalChargeCapacity: number("NominalChargeCapacity"),
            appleRawMaxCapacity: number("AppleRawMaxCapacity"),
            designCapacity: number("DesignCapacity"),
            temperatureRaw: number("Temperature"),
            isCharging: flag("IsCharging"),
            externalConnected: flag("ExternalConnected"),
            externalChargeCapable: flag("ExternalChargeCapable"),
            fullyCharged: flag("FullyCharged"),
            amperageMilliAmps: number("InstantAmperage") ?? number("Amperage"),
            voltageMilliVolts: number("Voltage"),
            cycleCount: number("CycleCount")
        )
    }
}

private enum IOKitDynamically {
    static let handle: UnsafeMutableRawPointer? = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)

    static func service(_ name: String) -> UInt32? {
        guard let handle = handle,
            let matchingSym = dlsym(handle, "IOServiceMatching"),
            let getSym = dlsym(handle, "IOServiceGetMatchingService")
        else { return nil }
        typealias Matching = @convention(c) (UnsafePointer<CChar>) -> Unmanaged<CFMutableDictionary>?
        typealias Get = @convention(c) (UInt32, CFDictionary) -> UInt32
        let matching = unsafeBitCast(matchingSym, to: Matching.self)
        let get = unsafeBitCast(getSym, to: Get.self)
        guard let dict = name.withCString({ matching($0) })?.takeRetainedValue() else { return nil }
        let service = get(0, dict)
        return service == 0 ? nil : service
    }

    static func properties(_ service: UInt32) -> [String: Any]? {
        guard let handle = handle, let sym = dlsym(handle, "IORegistryEntryCreateCFProperties") else { return nil }
        typealias Copy = @convention(c) (UInt32, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>, CFAllocator?, UInt32) -> Int32
        let copy = unsafeBitCast(sym, to: Copy.self)
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard copy(service, &unmanaged, kCFAllocatorDefault, 0) == 0, let dict = unmanaged?.takeRetainedValue() as? [String: Any] else { return nil }
        return dict
    }

    static func release(_ service: UInt32) {
        guard let handle = handle, let sym = dlsym(handle, "IOObjectRelease") else { return }
        typealias Release = @convention(c) (UInt32) -> Int32
        _ = unsafeBitCast(sym, to: Release.self)(service)
    }
}

private func matchingService(_ name: String) -> UInt32? { IOKitDynamically.service(name) }
private func copyProperties(_ service: UInt32) -> [String: Any]? { IOKitDynamically.properties(service) }
private func release(_ service: UInt32) { IOKitDynamically.release(service) }

enum BatteryCareClient {
    static func send(_ operation: BatteryCareOp) -> Bool {
        XALog.write(XALog.net, "battery care op")
        guard let token = try? String(contentsOfFile: BatteryCarePaths.token, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
            !token.isEmpty
        else { return false }
        let command: String
        switch operation {
        case .status: command = "status"
        case .setCharging(true): command = "charge-on"
        case .setCharging(false):
            if FileManager.default.fileExists(atPath: BatteryCarePaths.killSwitch) { return send(.restore) }
            command = "charge-off"
        case .restore: command = "restore"
        }
        guard BatteryCareOp.parse(command) != nil else { return false }
        return write(token: token, command: command)
    }

    private static func write(token: String, command: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = Array(BatteryCarePaths.socket.utf8)
        guard path.count < MemoryLayout.size(ofValue: address.sun_path) else { return false }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: path)
        }
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, length) }
        }
        guard connected == 0 else { return false }
        var bytes = Array("\(token)\n\(command)\n".utf8)
        let sent = bytes.withUnsafeMutableBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
        return sent > 0
    }
}

final class BatteryCareLoop {
    private var session = ChargeSession()
    private var previousLevel: Double?
    private var previousAt: Date?
    private var lastGoodAt: Date?
    private(set) var warning: String?
    private(set) var lastText = ""

    func tick(enabledTelemetry: Bool, chargeLimit: Bool, config: ChargeLimitConfig) -> (text: String, heat: Bool) {
        let kill = FileManager.default.fileExists(atPath: BatteryCarePaths.killSwitch)
        let registry = BatteryRegistry.read()
        UIDevice.current.isBatteryMonitoringEnabled = true
        let deviceLevel = Double(UIDevice.current.batteryLevel)
        let deviceCharging: Bool?
        switch UIDevice.current.batteryState {
        case .charging, .full: deviceCharging = true
        case .unplugged: deviceCharging = false
        default: deviceCharging = nil
        }
        let sample: BatterySample
        let readFailed: Bool
        if let registry = registry {
            sample = BatteryReading.sample(
                raw: registry,
                deviceLevel: deviceLevel < 0 ? nil : deviceLevel,
                deviceCharging: deviceCharging,
                cycleCount: nil
            )
            readFailed = false
            lastGoodAt = Date()
        } else if deviceLevel >= 0 {
            sample = BatteryReading.sample(raw: RawBatteryProperties(), deviceLevel: deviceLevel, deviceCharging: deviceCharging, cycleCount: nil)
            readFailed = false
            lastGoodAt = Date()
        } else {
            sample = BatterySample()
            readFailed = true
        }
        let now = Date()
        let age = lastGoodAt.map { now.timeIntervalSince($0) }
        let watchdog = ChargeWatchdog.decide(
            WatchdogInput(
                telemetryAgeSeconds: age,
                readFailed: readFailed,
                levelPercent: sample.levelPercent,
                previousLevelPercent: previousLevel,
                secondsSincePrevious: previousAt.map { now.timeIntervalSince($0) },
                chargingPaused: session.paused,
                externalConnected: sample.externalConnected,
                temperatureC: sample.temperatureC
            ))
        if chargeLimit {
            let command = session.step(enabled: true, killSwitch: kill, levelPercent: sample.levelPercent, watchdog: watchdog, config: config)
            apply(command)
            warning = watchdog == .none ? nil : "Charge limit paused: \(watchdog). Normal charging restored."
        } else if session.paused {
            apply(session.step(enabled: false, killSwitch: false, levelPercent: sample.levelPercent, watchdog: .none, config: config))
            warning = nil
        }
        if let level = sample.levelPercent {
            previousLevel = level
            previousAt = now
        }
        if enabledTelemetry, BatteryDisplay.shouldDim(temperatureC: sample.temperatureC) {
            UIScreen.main.brightness = min(UIScreen.main.brightness, 0.35)
        }
        lastText = BatteryDisplay.menuText(sample)
        let text = enabledTelemetry ? lastText : ""
        return (text, BatteryDisplay.shouldDim(temperatureC: sample.temperatureC))
    }

    func restore() {
        _ = session.step(enabled: false, killSwitch: false, levelPercent: nil, watchdog: .none, config: ChargeLimitConfig())
        _ = BatteryCareClient.send(.restore)
        warning = nil
    }

    func disable() {
        let directory = (BatteryCarePaths.killSwitch as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: BatteryCarePaths.killSwitch, contents: Data("disabled\n".utf8))
        restore()
    }

    private func apply(_ command: ChargeCommand) {
        switch command {
        case .none: break
        case .stopCharging: _ = BatteryCareClient.send(.setCharging(false))
        case .resumeCharging: _ = BatteryCareClient.send(.restore)
        }
    }
}
