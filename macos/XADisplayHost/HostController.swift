@preconcurrency import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import Darwin
@preconcurrency import Foundation
@preconcurrency import Network
@preconcurrency import ScreenCaptureKit
import XADisplayProtocol

final class HostController: @unchecked Sendable {
    var onState: ((String) -> Void)?
    var onPhase: ((ConnectionPhase) -> Void)?
    let poster = EventPoster()
    let capture = CapturePipeline()
    let audioCapture = AudioCapture()
    var audioMode: AudioRouteMode = HostStore.loadAudioMode()
    var selectedAudioBundles: [String] = HostStore.loadAudioBundles()
    var knownAudioApps: [(bundle: String, name: String)] = []
    let display = XAVirtualDisplay()
    var dispatcher: InputDispatcher
    var settings: XAFeatureSettings
    var token: String
    var library: PresetLibrary
    var adaptation: AdaptationController
    var preset: StreamPreset
    var portrait = false
    var lastDeviceOrientation = "landscape"
    var transport: TransportKind = .none
    var videoParser = FrameParser(limits: .video)
    var inputParser = FrameParser(limits: .input)
    var usbFD: FDStream?
    var wifiVideo: NWConnection?
    var wifiInput: NWConnection?
    var inputFD: FDStream?
    var browser: NWBrowser?
    var wakeListener: NWListener?
    var wifiHost: String?
    var timer: Timer?
    var lastDisplayFrame = XARect(x: 0, y: 0, width: 0, height: 0)
    var savedDisplayID: CGDirectDisplayID = 0
    var pendingSends = 0
    var sendBudget = SendBudget()
    var clipboardRevision: UInt64 = 0
    var pasteboardCount = NSPasteboard.general.changeCount
    var logs: [String] = []
    var running = false
    var userPaused = false
    let queue = DispatchQueue(label: "xa.host")
    let session = SessionCoordinator()
    var channelGate: ChannelGate
    var pendingHello: LegacyHello?
    var lastLatency = "—"
    var lastFPS = "—"
    var displayedPhase = ConnectionPhase.idle
    var logRing = LogRing()

    init() {
        let stored = HostStore.load()
        settings = stored.settings
        token = stored.token
        library = PresetLibrary(enabled: settings.savedPresets, items: stored.presets)
        if settings.savedPresets, let first = library.items.last {
            preset = StreamPreset.preset(first.preset).oriented(portrait: first.portrait)
            portrait = first.portrait
        } else {
            preset = .balanced
        }
        adaptation = AdaptationController(preset: preset.id, usb: true)
        dispatcher = InputDispatcher(
            expectedToken: token,
            requirePairing: settings.requirePairing,
            clipboardEnabled: settings.clipboardSync,
            windowActionsEnabled: settings.windowSnapping || settings.touchscreenGestures,
            mediaEnabled: settings.mediaRemote
        )
        channelGate = ChannelGate(requireAuth: settings.requirePairing)
        dispatcher.sessionGenerator = {
            var value: UInt32 = 0
            arc4random_buf(&value, MemoryLayout<UInt32>.size)
            return value == 0 ? 1 : value
        }
    }

    func start() {
        running = true
        userPaused = false
        transition(.startDiscovery)
        log("XA Display Host started")
        startBrowser()
        startWakeService()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.pollClipboard()
            self?.publishChrome()
            self?.publishNowPlaying()
            self?.queue.async { self?.tick() }
        }
        queue.async { self.tick() }
        publish()
    }

    func stop() {
        running = false
        timer?.invalidate()
        let main = WindowMover.mainDisplayFrame()
        if lastDisplayFrame.width > 0 {
            let moved = WindowMover.recover(from: lastDisplayFrame, to: main)
            log("Recovered \(moved) window(s) onto the main display")
        }
        capture.stop()
        audioCapture.stop()
        display.stop()
        wakeListener?.cancel()
        wakeListener = nil
        closeLinks()
        publish()
    }

    func currentToken() -> String { token }

    func regenerateToken() {
        token = PairingToken.make()
        dispatcher.expectedToken = token
        dispatcher.requirePairing = settings.requirePairing
        HostStore.save(token: token, settings: settings, presets: library.items)
        log("Pairing token regenerated")
        publish()
    }

    func setRequirePairing(_ on: Bool) {
        settings.requirePairing = on
        dispatcher.requirePairing = on
        channelGate.requireAuth = on
        persist()
    }

    func setUserPaused(_ paused: Bool) {
        userPaused = paused
        if paused {
            closeLinks()
            transport = .none
            transition(.userStop)
        } else {
            transition(.retry)
            queue.async { self.tick() }
        }
        publish()
    }

    func setClipboard(_ on: Bool) {
        settings.clipboardSync = on
        dispatcher.clipboardEnabled = on
        persist()
    }

    func setAudio(_ on: Bool) {
        settings.audio = on
        persist()
        restartAudio()
    }

    func setAudioMode(_ mode: AudioRouteMode) {
        audioMode = mode
        HostStore.saveAudio(mode: mode, bundles: selectedAudioBundles)
        restartAudio()
    }

    func toggleAudioBundle(_ bundle: String) {
        if let index = selectedAudioBundles.firstIndex(of: bundle) {
            selectedAudioBundles.remove(at: index)
        } else {
            selectedAudioBundles.append(bundle)
        }
        HostStore.saveAudio(mode: audioMode, bundles: selectedAudioBundles)
        if audioMode == .selected { restartAudio() }
    }

    func audioMenuState() -> (mode: AudioRouteMode, selected: [String], apps: [(bundle: String, name: String)]) {
        (audioMode, selectedAudioBundles, knownAudioApps)
    }

    func setWindowSnapping(_ on: Bool) {
        settings.windowSnapping = on
        dispatcher.windowActionsEnabled = on || settings.touchscreenGestures
        persist()
    }

    func setTouchGestures(_ on: Bool) {
        settings.touchscreenGestures = on
        dispatcher.windowActionsEnabled = settings.windowSnapping || on
        persist()
    }

    func setWiFi(_ on: Bool) {
        settings.wifiFallback = on
        persist()
        startWakeService()
    }

    func setOneTapReconnect(_ on: Bool) {
        settings.oneTapReconnect = on
        persist()
        startWakeService()
    }

    func setRememberMacs(_ on: Bool) {
        settings.rememberMacs = on
        persist()
    }

    func setMediaRemote(_ on: Bool) {
        settings.mediaRemote = on
        dispatcher.mediaEnabled = on
        persist()
    }

    func setAutoConnect(_ on: Bool) {
        settings.autoConnectUSB = on
        persist()
        if on { tick() }
    }

    func setLowLatencyWiFi(_ on: Bool) {
        settings.lowLatencyWiFi = on
        persist()
    }

    func setSavedPresets(_ on: Bool) {
        settings.savedPresets = on
        library.enabled = on
        persist()
    }

    func selectPreset(_ id: StreamPreset.ID) {
        preset = StreamPreset.preset(id).oriented(portrait: portrait)
        adaptation = AdaptationController(preset: id, usb: transport != .wifi)
        if settings.savedPresets {
            library.save(SavedDisplayPreset(name: "Last", preset: id, portrait: portrait))
        }
        persist()
        rebuildDisplay()
    }

    func saveNamedPreset(_ name: String) {
        guard settings.savedPresets else { return }
        library.save(SavedDisplayPreset(name: name, preset: preset.id, portrait: portrait))
        persist()
    }

    func diagnostics() -> String {
        DiagnosticsText.render(
            DiagnosticsSnapshot(
                appVersion: "1.0.0",
                transport: transport.rawValue,
                preset: "\(preset.id.rawValue) \(preset.width)x\(preset.height)@\(adaptation.fps)",
                permissions: [
                    "screenRecording": CGPreflightScreenCaptureAccess(),
                    "accessibility": AXIsProcessTrusted()
                ],
                pairingToken: token,
                thermal: "mac",
                battery: "mac",
                notes: logs.suffix(12).map { $0 }
            ))
    }

    func settingsSnapshot() -> XAFeatureSettings { settings }
    func batterySummary() -> String { lastBatteryText }
    func settingsDocument() -> XASettingsDocument {
        XASettingsDocument(
            features: settings,
            audioVolume: 1,
            audioMode: audioMode.rawValue,
            preset: preset.id.rawValue,
            pairedIDs: pairedIDs
        )
    }

    var lastHealth = HealthReport(thermal: .unknown, batteryFraction: nil, batteryState: "unknown", fpsDelivered: 0, decodeFails: 0)
    var lastBatteryText = "iPad battery: waiting"
    var lastBatteryHeat = false
    var pairedIDs: [String] = []
    var applyingRemoteSettings = false
    let udpSender = UDPVideoSender()
    var udpSequence: UInt16 = 1
    var udpFrameID: UInt16 = 1
    var linkTuner = WiFiLinkTuner()
    var ackJitter = JitterEstimate()

}

enum HostStore {
    static let tokenKey = "XADisplayHost.token"
    static let settingsKey = "XADisplayHost.features"
    static let presetsKey = "XADisplayHost.presets"

    static func load() -> (token: String, settings: XAFeatureSettings, presets: [SavedDisplayPreset]) {
        let defaults = UserDefaults.standard
        var token = defaults.string(forKey: tokenKey) ?? ""
        if token.isEmpty {
            token = PairingToken.make()
            defaults.set(token, forKey: tokenKey)
        }
        let settings = defaults.data(forKey: settingsKey).flatMap { try? JSONDecoder().decode(XAFeatureSettings.self, from: $0) } ?? XAFeatureSettings()
        let presets = defaults.data(forKey: presetsKey).flatMap { try? JSONDecoder().decode([SavedDisplayPreset].self, from: $0) } ?? []
        return (token, settings, presets)
    }

    static func save(token: String, settings: XAFeatureSettings, presets: [SavedDisplayPreset]) {
        let defaults = UserDefaults.standard
        defaults.set(token, forKey: tokenKey)
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: settingsKey) }
        if let data = try? JSONEncoder().encode(presets) { defaults.set(data, forKey: presetsKey) }
    }

    static func loadAudioMode() -> AudioRouteMode {
        AudioRouteMode(rawValue: UserDefaults.standard.string(forKey: "XADisplayHost.audioMode") ?? "") ?? .all
    }

    static func loadAudioBundles() -> [String] {
        UserDefaults.standard.stringArray(forKey: "XADisplayHost.audioBundles") ?? []
    }

    static func saveAudio(mode: AudioRouteMode, bundles: [String]) {
        UserDefaults.standard.set(mode.rawValue, forKey: "XADisplayHost.audioMode")
        UserDefaults.standard.set(bundles, forKey: "XADisplayHost.audioBundles")
    }
}
