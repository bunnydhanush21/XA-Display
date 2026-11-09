import Foundation

/// RawBatteryProperties.
public struct RawBatteryProperties: Equatable {
    public var currentCapacity: Double?
    public var maxCapacity: Double?
    public var nominalChargeCapacity: Double?
    public var appleRawMaxCapacity: Double?
    public var designCapacity: Double?
    public var temperatureRaw: Double?
    public var isCharging: Bool?
    public var externalConnected: Bool?
    public var externalChargeCapable: Bool?
    public var fullyCharged: Bool?
    public var amperageMilliAmps: Double?
    public var voltageMilliVolts: Double?
    public var cycleCount: Double?

    public init(
        currentCapacity: Double? = nil,
        maxCapacity: Double? = nil,
        nominalChargeCapacity: Double? = nil,
        appleRawMaxCapacity: Double? = nil,
        designCapacity: Double? = nil,
        temperatureRaw: Double? = nil,
        isCharging: Bool? = nil,
        externalConnected: Bool? = nil,
        externalChargeCapable: Bool? = nil,
        fullyCharged: Bool? = nil,
        amperageMilliAmps: Double? = nil,
        voltageMilliVolts: Double? = nil,
        cycleCount: Double? = nil
    ) {
        self.currentCapacity = currentCapacity
        self.maxCapacity = maxCapacity
        self.nominalChargeCapacity = nominalChargeCapacity
        self.appleRawMaxCapacity = appleRawMaxCapacity
        self.designCapacity = designCapacity
        self.temperatureRaw = temperatureRaw
        self.isCharging = isCharging
        self.externalConnected = externalConnected
        self.externalChargeCapable = externalChargeCapable
        self.fullyCharged = fullyCharged
        self.amperageMilliAmps = amperageMilliAmps
        self.voltageMilliVolts = voltageMilliVolts
        self.cycleCount = cycleCount
    }
}

/// BatterySample.
public struct BatterySample: Equatable {
    public var levelPercent: Double?
    public var cycleCount: Int?
    public var healthFraction: Double?
    public var temperatureC: Double?
    public var isCharging: Bool?
    public var externalConnected: Bool?
    public var externalChargeCapable: Bool?
    public var fullyCharged: Bool?
    public var amperageMilliAmps: Int?
    public var voltageMilliVolts: Int?
    public var source: String

    public init(
        levelPercent: Double? = nil,
        cycleCount: Int? = nil,
        healthFraction: Double? = nil,
        temperatureC: Double? = nil,
        isCharging: Bool? = nil,
        externalConnected: Bool? = nil,
        externalChargeCapable: Bool? = nil,
        fullyCharged: Bool? = nil,
        amperageMilliAmps: Int? = nil,
        voltageMilliVolts: Int? = nil,
        source: String = "none"
    ) {
        self.levelPercent = levelPercent
        self.cycleCount = cycleCount
        self.healthFraction = healthFraction
        self.temperatureC = temperatureC
        self.isCharging = isCharging
        self.externalConnected = externalConnected
        self.externalChargeCapable = externalChargeCapable
        self.fullyCharged = fullyCharged
        self.amperageMilliAmps = amperageMilliAmps
        self.voltageMilliVolts = voltageMilliVolts
        self.source = source
    }
}

/// BatteryTemperature.
public enum BatteryTemperature {
    /// Registry temperature is often centi-degrees C. A value already in a human range is left as degrees.
    /// Out-of-range numbers become nil so the UI can say unavailable instead of 0.
    public static func celsius(raw: Double) -> Double? {
        guard raw.isFinite else { return nil }
        if raw >= -10, raw <= 80 { return raw }
        if abs(raw) >= 1_000 {
            let centi = raw / 100
            return (centi >= -10 && centi <= 80) ? centi : nil
        }
        let deci = raw / 10
        return (deci >= -10 && deci <= 80) ? deci : nil
    }
}

/// BatteryHealth.
public enum BatteryHealth {
    public static func fraction(nominal: Double?, appleRawMax: Double?, design: Double?) -> Double? {
        guard let design = design, design > 0, design.isFinite else { return nil }
        let numerator = (nominal ?? 0) > 0 ? nominal : appleRawMax
        guard let numerator = numerator, numerator > 0, numerator.isFinite else { return nil }
        let ratio = numerator / design
        guard ratio >= 0.4, ratio <= 1.05 else { return nil }
        return ratio
    }
}

/// BatteryElectrical.
public enum BatteryElectrical {
    public static func milliamps(_ raw: Double?) -> Int? {
        guard let raw = raw, raw.isFinite, raw >= -8_000, raw <= 8_000 else { return nil }
        return Int(raw.rounded())
    }

    public static func millivolts(_ raw: Double?) -> Int? {
        guard let raw = raw, raw.isFinite else { return nil }
        let milli = raw < 20 ? raw * 1_000 : raw
        guard milli >= 2_000, milli <= 5_000 else { return nil }
        return Int(milli.rounded())
    }
}

/// BatteryReading.
public enum BatteryReading {
    public static func sample(raw: RawBatteryProperties, deviceLevel: Double?, deviceCharging: Bool?, cycleCount: Int?) -> BatterySample {
        var sample = BatterySample(source: "registry")
        if let current = raw.currentCapacity, let max = raw.maxCapacity, max > 0, current >= 0 {
            let percent = current / max * 100
            if percent >= 0, percent <= 100 { sample.levelPercent = percent }
        }
        if sample.levelPercent == nil, let deviceLevel = deviceLevel, deviceLevel >= 0, deviceLevel <= 1 {
            sample.levelPercent = deviceLevel * 100
            sample.source = "uidevice"
        }
        let cycles = cycleCount ?? raw.cycleCount.map { Int($0.rounded()) }
        if let cycles = cycles, cycles >= 0, cycles < 10_000 { sample.cycleCount = cycles }
        sample.healthFraction = BatteryHealth.fraction(
            nominal: raw.nominalChargeCapacity,
            appleRawMax: raw.appleRawMaxCapacity,
            design: raw.designCapacity
        )
        if let temperature = raw.temperatureRaw {
            sample.temperatureC = BatteryTemperature.celsius(raw: temperature)
        }
        sample.isCharging = raw.isCharging ?? deviceCharging
        sample.externalConnected = raw.externalConnected
        sample.externalChargeCapable = raw.externalChargeCapable
        sample.fullyCharged = raw.fullyCharged
        sample.amperageMilliAmps = BatteryElectrical.milliamps(raw.amperageMilliAmps)
        sample.voltageMilliVolts = BatteryElectrical.millivolts(raw.voltageMilliVolts)
        return sample
    }
}

/// BatteryDisplay.
public enum BatteryDisplay {
    public static let dimAtCelsius = 35.0

    public static func shouldDim(temperatureC: Double?) -> Bool {
        guard let temperatureC = temperatureC else { return false }
        return temperatureC >= dimAtCelsius
    }

    public static func menuText(_ sample: BatterySample) -> String {
        [
            "Level: \(percent(sample.levelPercent))",
            "Cycles: \(integer(sample.cycleCount))",
            "Health: \(health(sample.healthFraction))",
            "Temperature: \(temperature(sample.temperatureC))",
            "Charging: \(flag(sample.isCharging))",
            "External: \(flag(sample.externalConnected))",
            "Charge capable: \(flag(sample.externalChargeCapable))",
            "Full: \(flag(sample.fullyCharged))",
            "Current: \(milli(sample.amperageMilliAmps, unit: "mA"))",
            "Voltage: \(milli(sample.voltageMilliVolts, unit: "mV"))",
            "Source: \(sample.source)"
        ].joined(separator: "\n")
    }

    private static func percent(_ value: Double?) -> String {
        guard let value = value else { return "unavailable" }
        return String(format: "%.0f%%", value)
    }

    private static func integer(_ value: Int?) -> String {
        guard let value = value else { return "unavailable" }
        return String(value)
    }

    private static func health(_ value: Double?) -> String {
        guard let value = value else { return "unavailable" }
        return String(format: "%.0f%%", value * 100)
    }

    private static func temperature(_ value: Double?) -> String {
        guard let value = value else { return "unavailable" }
        return String(format: "%.1f C", value)
    }

    private static func flag(_ value: Bool?) -> String {
        guard let value = value else { return "unavailable" }
        return value ? "yes" : "no"
    }

    private static func milli(_ value: Int?, unit: String) -> String {
        guard let value = value else { return "unavailable" }
        return "\(value) \(unit)"
    }
}

/// ChargeLimitConfig.
public struct ChargeLimitConfig: Equatable, Codable {
    public var stopAtPercent: Double
    public var resumeAtPercent: Double

    public init(stopAtPercent: Double = 80, resumeAtPercent: Double = 75) {
        self.stopAtPercent = stopAtPercent
        self.resumeAtPercent = resumeAtPercent
    }

    public func validated() -> ChargeLimitConfig {
        var stop = min(100, max(60, stopAtPercent))
        var resume = min(resumeAtPercent, stop - 5)
        if resume < 21 { resume = 21 }
        if stop < resume + 5 { stop = min(100, resume + 5) }
        return ChargeLimitConfig(stopAtPercent: stop, resumeAtPercent: resume)
    }
}

/// ChargeCommand.
public enum ChargeCommand: Equatable {
    case none
    case stopCharging
    case resumeCharging
}

/// WatchdogTrigger.
public enum WatchdogTrigger: Equatable {
    case none
    case staleTelemetry
    case readError
    case unexpectedDrain
    case lowBattery
    case temperature
}

/// WatchdogInput.
public struct WatchdogInput: Equatable {
    public var telemetryAgeSeconds: Double?
    public var readFailed: Bool
    public var levelPercent: Double?
    public var previousLevelPercent: Double?
    public var secondsSincePrevious: Double?
    public var chargingPaused: Bool
    public var externalConnected: Bool?
    public var temperatureC: Double?

    public init(
        telemetryAgeSeconds: Double? = 0,
        readFailed: Bool = false,
        levelPercent: Double? = nil,
        previousLevelPercent: Double? = nil,
        secondsSincePrevious: Double? = nil,
        chargingPaused: Bool = false,
        externalConnected: Bool? = nil,
        temperatureC: Double? = nil
    ) {
        self.telemetryAgeSeconds = telemetryAgeSeconds
        self.readFailed = readFailed
        self.levelPercent = levelPercent
        self.previousLevelPercent = previousLevelPercent
        self.secondsSincePrevious = secondsSincePrevious
        self.chargingPaused = chargingPaused
        self.externalConnected = externalConnected
        self.temperatureC = temperatureC
    }
}

/// ChargeWatchdog.
public enum ChargeWatchdog {
    public static let staleSeconds = 30.0
    public static let lowBatteryPercent = 20.0
    public static let maxTemperatureC = 40.0
    public static let unexpectedDrainPoints = 2.0

    public static func decide(_ input: WatchdogInput) -> WatchdogTrigger {
        if input.readFailed { return .readError }
        if input.telemetryAgeSeconds == nil || (input.telemetryAgeSeconds ?? 0) > staleSeconds { return .staleTelemetry }
        if let temperature = input.temperatureC, temperature > maxTemperatureC { return .temperature }
        if let level = input.levelPercent, level < lowBatteryPercent { return .lowBattery }
        if input.chargingPaused, input.externalConnected == true,
            let level = input.levelPercent, let previous = input.previousLevelPercent,
            let dt = input.secondsSincePrevious, dt > 0, dt <= 120, previous - level >= unexpectedDrainPoints
        {
            return .unexpectedDrain
        }
        return .none
    }
}

/// ChargeSession.
public struct ChargeSession: Equatable {
    public private(set) var paused = false

    public init(paused: Bool = false) { self.paused = paused }

    public mutating func step(enabled: Bool, killSwitch: Bool, levelPercent: Double?, watchdog: WatchdogTrigger, config: ChargeLimitConfig) -> ChargeCommand {
        let limits = config.validated()
        if !enabled || killSwitch || watchdog != .none {
            return resumeIfPaused()
        }
        guard let levelPercent = levelPercent else { return .none }
        if !paused, levelPercent >= limits.stopAtPercent {
            paused = true
            return .stopCharging
        }
        if paused, levelPercent <= limits.resumeAtPercent {
            return resumeIfPaused()
        }
        return .none
    }

    private mutating func resumeIfPaused() -> ChargeCommand {
        guard paused else { return .none }
        paused = false
        return .resumeCharging
    }
}

/// BatteryCareOp.
public enum BatteryCareOp: Equatable {
    case status
    case setCharging(Bool)
    case restore

    /// Fixed allow-list. DisableInflow and ExternalConnected are not operations.
    public static func parse(_ line: String) -> BatteryCareOp? {
        switch line.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "status": return .status
        case "charge-on": return .setCharging(true)
        case "charge-off": return .setCharging(false)
        case "restore": return .restore
        default: return nil
        }
    }
}

/// BatteryCarePaths.
public enum BatteryCarePaths {
    public static let killSwitch = "/var/mobile/Library/XADisplay/battery-care.disabled"
    public static let token = "/var/mobile/Library/XADisplay/battery-care.token"
    public static let socket = "/var/run/xadisplay-battery.sock"
}

/// HeatResponse.
public enum HeatResponse {
    public static let touchesThermalControls = false
    public static func bitrateFactor(temperatureC: Double?) -> Double {
        BatteryDisplay.shouldDim(temperatureC: temperatureC) ? 0.7 : 1
    }
}
