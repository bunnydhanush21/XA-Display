@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import XADisplayProtocol

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var retained: AppDelegate?

    static func retainForLaunch(_ delegate: AppDelegate) { retained = delegate }

    var statusButtonForTest: NSStatusBarButton? { statusItem?.button }
    private var controller: HostController!
    private var statusItem: NSStatusItem!
    private var onboarding: OnboardingFlow?
    private var settingsPanel: HostSettingsPanel?
    private let menu = MenuPopoverController()
    private var phase = ConnectionPhase.idle
    private var menuPace = UIPace(interval: 0.5)

    func applicationDidFinishLaunching(_ notification: Notification) {
        XALog.write(XALog.ui, "host launch")
        if let path = ProcessInfo.processInfo.environment["XA_LAUNCH_MARKER"], !path.isEmpty {
            try? Data("host launch\n".utf8).write(to: URL(fileURLWithPath: path))
        }
        NSApp.setActivationPolicy(.accessory)
        controller = HostController()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = StatusGlyph.image(phase: .idle)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        wireMenu()
        controller.onState = { [weak self] _ in self?.refreshMenu(force: false) }
        controller.onPhase = { [weak self] phase in
            self?.phase = phase
            self?.statusItem.button?.image = StatusGlyph.image(phase: phase)
            self?.refreshMenu(force: true)
        }
        refreshMenu()
        if !UserDefaults.standard.bool(forKey: "XADisplayHost.didOnboard") || !CGPreflightScreenCaptureAccess() || !AXIsProcessTrusted() {
            showOnboarding()
        }
        controller.start()
        LoginItem.setEnabled(controller.settingsSnapshot().launchAtLogin)
    }

    func applicationWillTerminate(_ notification: Notification) { controller.stop() }

    private func wireMenu() {
        menu.onConnect = { [weak self] in self?.controller.setUserPaused(false) }
        menu.onDisconnect = { [weak self] in self?.controller.setUserPaused(true) }
        menu.onPreset = { [weak self] id in self?.controller.selectPreset(id) }
        menu.onCustom = { [weak self] in self?.showSettings() }
        menu.onToggle = { [weak self] id, on in self?.applyToggle(id, on) }
        menu.onArrange = { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Displays.prefPane")) }
        menu.onSettings = { [weak self] in self?.showSettings() }
        menu.onDiagnostics = { [weak self] in self?.exportDiagnostics() }
        menu.onQuit = { [weak self] in
            self?.controller.stop()
            NSApp.terminate(nil)
        }
        menu.onFixPermissions = { [weak self] in self?.showOnboarding() }
    }

    private func applyToggle(_ id: String, _ on: Bool) {
        switch id {
        case "audio": controller.setAudio(on)
        case "clipboard": controller.setClipboard(on)
        case "touch": controller.setTouchGestures(on)
        case "latency": controller.setLowLatencyWiFi(on)
        default: break
        }
        refreshMenu()
    }

    private func refreshMenu(force: Bool = false) {
        guard menuPace.allow(now: Date(), force: force) else { return }
        var snapshot = controller.menuSnapshot()
        snapshot.phase = phase
        menu.refresh(snapshot)
        statusItem.button?.toolTip = snapshot.peerName
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if menu.popover.isShown {
            menu.popover.performClose(nil)
        } else {
            refreshMenu()
            menu.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc private func showSettings() {
        let panel = settingsPanel ?? HostSettingsPanel(document: controller.settingsDocument())
        settingsPanel = panel
        panel.update(controller.settingsDocument())
        let audio = controller.audioMenuState()
        panel.apps = audio.apps
        panel.selectedBundles = audio.selected
        panel.onToggleApp = { [weak self] bundle in self?.controller.toggleAudioBundle(bundle) }
        panel.onChange = { [weak self] document in self?.controller.applyLocalDocument(document, broadcast: true) }
        panel.onRevoke = { [weak self] in self?.controller.regenerateToken() }
        panel.onDiagnostics = { [weak self] in self?.exportDiagnostics() }
        panel.onScreen = { CGRequestScreenCaptureAccess() }
        panel.onAccessibility = {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
        panel.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showOnboarding() {
        let flow = onboarding ?? OnboardingFlow()
        onboarding = flow
        flow.pairingCode = controller.currentToken()
        flow.onFinish = { UserDefaults.standard.set(true, forKey: "XADisplayHost.didOnboard") }
        flow.show()
    }

    @objc private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "XADisplay-diagnostics.zip"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let text = self?.controller.diagnostics() else { return }
            let zip = StoredZip.archive(name: "diagnostics.txt", data: Data(text.utf8))
            try? zip.write(to: url)
        }
    }
}
