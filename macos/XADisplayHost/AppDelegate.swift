import AppKit
import ApplicationServices
import XADisplayProtocol

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: HostController!
    private var statusItem: NSStatusItem!
    private var onboarding: NSWindow?
    private var settingsPanel: HostSettingsPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller = HostController()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "XA"
        controller.onState = { [weak self] state in
            self?.statusItem.button?.title = "XA"
            self?.statusItem.button?.toolTip = state
            self?.rebuildMenu(state: state)
        }
        rebuildMenu(state: "starting")
        if !CGPreflightScreenCaptureAccess() || !AXIsProcessTrusted() {
            showOnboarding()
        }
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    private func rebuildMenu(state: String) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: state, action: nil, keyEquivalent: "")
        let settings = controller.settingsSnapshot()
        menu.addItem(withTitle: "Pairing token \(DiagnosticsText.redactToken(controller.currentToken()))", action: #selector(copyToken), keyEquivalent: "")
        menu.addItem(withTitle: "Regenerate token", action: #selector(regenerate), keyEquivalent: "")
        addToggle(menu, "Require pairing", settings.requirePairing, #selector(togglePairing(_:)))
        addToggle(menu, "Clipboard sync", settings.clipboardSync, #selector(toggleClipboard(_:)))
        addToggle(menu, "Audio to iPad", settings.audio, #selector(toggleAudio(_:)))
        let audioMenu = NSMenu()
        let audioState = controller.audioMenuState()
        let modes: [(String, AudioRouteMode)] = [
            ("All system audio", .all),
            ("Selected apps only", .selected),
            ("Apps on the iPad display", .displayApps)
        ]
        for (index, mode) in modes.enumerated() {
            let item = NSMenuItem(title: mode.0, action: #selector(audioMode(_:)), keyEquivalent: "")
            item.tag = index
            item.state = audioState.mode == mode.1 ? .on : .off
            item.target = self
            audioMenu.addItem(item)
        }
        audioMenu.addItem(NSMenuItem(title: "Mute on Mac is unavailable without a virtual audio device", action: nil, keyEquivalent: ""))
        if audioState.mode == .selected {
            audioMenu.addItem(.separator())
            for app in audioState.apps.prefix(24) where !app.bundle.isEmpty {
                let item = NSMenuItem(title: app.name.isEmpty ? app.bundle : app.name, action: #selector(toggleAudioApp(_:)), keyEquivalent: "")
                item.representedObject = app.bundle
                item.state = audioState.selected.contains(app.bundle) ? .on : .off
                item.target = self
                audioMenu.addItem(item)
            }
        }
        let audioItem = NSMenuItem(title: "Audio route", action: nil, keyEquivalent: "")
        audioItem.submenu = audioMenu
        menu.addItem(audioItem)
        addToggle(menu, "Window snapping", settings.windowSnapping, #selector(toggleSnap(_:)))
        addToggle(menu, "Touch-style window gestures", settings.touchscreenGestures, #selector(toggleTouch(_:)))
        let touchNote = NSMenuItem(title: "Pointer and Accessibility actions, not native touch", action: nil, keyEquivalent: "")
        touchNote.isEnabled = false
        menu.addItem(touchNote)
        addToggle(menu, "Wi-Fi fallback", settings.wifiFallback, #selector(toggleWiFi(_:)))
        addToggle(menu, "One-tap reconnect", settings.oneTapReconnect, #selector(toggleOneTap(_:)))
        addToggle(menu, "Remember Macs", settings.rememberMacs, #selector(toggleRemember(_:)))
        addToggle(menu, "Media remote", settings.mediaRemote, #selector(toggleMedia(_:)))
        let wakeNote = NSMenuItem(title: "Wake uses Bonjour, not Wake-on-LAN", action: nil, keyEquivalent: "")
        wakeNote.isEnabled = false
        menu.addItem(wakeNote)
        addToggle(menu, "Auto-connect on USB", settings.autoConnectUSB, #selector(toggleAuto(_:)))
        addToggle(menu, "Saved presets", settings.savedPresets, #selector(toggleSaved(_:)))
        let presets = NSMenu()
        presets.addItem(withTitle: "Balanced 1440×1080", action: #selector(presetBalanced), keyEquivalent: "")
        presets.addItem(withTitle: "Safe 1024×768", action: #selector(presetSafe), keyEquivalent: "")
        presets.addItem(withTitle: "Native experimental 2048×1536", action: #selector(presetNative), keyEquivalent: "")
        presets.addItem(withTitle: "Save current as Last", action: #selector(savePreset), keyEquivalent: "")
        let presetItem = NSMenuItem(title: "Display preset", action: nil, keyEquivalent: "")
        presetItem.submenu = presets
        menu.addItem(presetItem)
        let batteryItem = NSMenuItem(title: "iPad battery", action: nil, keyEquivalent: "")
        let batteryMenu = NSMenu()
        for line in controller.batterySummary().split(separator: "\n").prefix(12) {
            let item = NSMenuItem(title: String(line), action: nil, keyEquivalent: "")
            item.isEnabled = false
            batteryMenu.addItem(item)
        }
        if batteryMenu.items.isEmpty {
            batteryMenu.addItem(NSMenuItem(title: "unavailable", action: nil, keyEquivalent: ""))
        }
        batteryItem.submenu = batteryMenu
        menu.addItem(batteryItem)
        menu.addItem(withTitle: "Permissions…", action: #selector(showPermissions), keyEquivalent: "")
        menu.addItem(withTitle: "Export diagnostics…", action: #selector(exportDiagnostics), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit XA Display Host", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        for item in presets.items { item.target = self }
        statusItem.menu = menu
    }

    private func addToggle(_ menu: NSMenu, _ title: String, _ on: Bool, _ action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.state = on ? .on : .off
        item.target = self
        menu.addItem(item)
    }

    @objc private func copyToken() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(controller.currentToken(), forType: .string)
    }
    @objc private func regenerate() { controller.regenerateToken() }
    @objc private func togglePairing(_ sender: NSMenuItem) { controller.setRequirePairing(sender.state != .on) }
    @objc private func toggleClipboard(_ sender: NSMenuItem) { controller.setClipboard(sender.state != .on) }
    @objc private func toggleAudio(_ sender: NSMenuItem) { controller.setAudio(sender.state != .on) }
    @objc private func audioMode(_ sender: NSMenuItem) {
        let modes: [AudioRouteMode] = [.all, .selected, .displayApps]
        guard sender.tag >= 0, sender.tag < modes.count else { return }
        controller.setAudioMode(modes[sender.tag])
    }
    @objc private func toggleAudioApp(_ sender: NSMenuItem) {
        guard let bundle = sender.representedObject as? String else { return }
        controller.toggleAudioBundle(bundle)
    }
    @objc private func toggleSnap(_ sender: NSMenuItem) { controller.setWindowSnapping(sender.state != .on) }
    @objc private func toggleTouch(_ sender: NSMenuItem) { controller.setTouchGestures(sender.state != .on) }
    @objc private func toggleWiFi(_ sender: NSMenuItem) { controller.setWiFi(sender.state != .on) }
    @objc private func toggleOneTap(_ sender: NSMenuItem) { controller.setOneTapReconnect(sender.state != .on) }
    @objc private func toggleRemember(_ sender: NSMenuItem) { controller.setRememberMacs(sender.state != .on) }
    @objc private func toggleMedia(_ sender: NSMenuItem) { controller.setMediaRemote(sender.state != .on) }
    @objc private func toggleAuto(_ sender: NSMenuItem) { controller.setAutoConnect(sender.state != .on) }
    @objc private func toggleSaved(_ sender: NSMenuItem) { controller.setSavedPresets(sender.state != .on) }
    @objc private func presetBalanced() { controller.selectPreset(.balanced) }
    @objc private func presetSafe() { controller.selectPreset(.safe) }
    @objc private func presetNative() { controller.selectPreset(.native) }
    @objc private func savePreset() { controller.saveNamedPreset("Last") }
    @objc private func showPermissions() { showOnboarding() }
    @objc private func showSettings() {
        let panel = settingsPanel ?? HostSettingsPanel(document: controller.settingsDocument())
        settingsPanel = panel
        panel.update(controller.settingsDocument())
        panel.onChange = { [weak self] document in
            self?.controller.applySharedSettings(SettingsSync.encode(document), broadcast: true)
        }
        panel.onRevoke = { [weak self] in self?.controller.regenerateToken() }
        panel.onScreen = { [weak self] in self?.requestScreen() }
        panel.onAccessibility = { [weak self] in self?.requestAccess() }
        panel.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func quit() {
        controller.stop()
        NSApp.terminate(nil)
    }

    @objc private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "XADisplay-diagnostics.txt"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let text = self?.controller.diagnostics() else { return }
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func showOnboarding() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 360), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "XA Display Host"
        let text = NSTextField(
            wrappingLabelWithString: """
                XA Display Host creates a virtual display and injects pointer and keyboard events. Those events are CGEvent mouse and keyboard events. They are not native Mac touchscreen input.

                Grant Screen Recording so this app can capture only the XA Display. Grant Accessibility so pointer, keyboard, and window recovery can work. Quit and reopen after granting Screen Recording if capture stays denied.

                USB is preferred. Wi-Fi is used only when the cable is gone and Wi-Fi fallback is enabled. Only a paired iPad can control the Mac while Require pairing is on.

                One-tap reconnect advertises this Mac as _xahost._tcp. The iPad's connection can wake the Mac when Wake for network access is already on. This app does not send Wake-on-LAN packets. Media remote sends play, skip, and volume as system media keys. It shows the frontmost app name because macOS has no public now-playing read API.
                """)
        text.frame = NSRect(x: 20, y: 120, width: 480, height: 210)
        let screen = NSButton(title: "Request Screen Recording", target: self, action: #selector(requestScreen))
        screen.frame = NSRect(x: 20, y: 70, width: 220, height: 32)
        let access = NSButton(title: "Request Accessibility", target: self, action: #selector(requestAccess))
        access.frame = NSRect(x: 250, y: 70, width: 220, height: 32)
        let close = NSButton(title: "Continue", target: self, action: #selector(closeOnboarding))
        close.frame = NSRect(x: 390, y: 20, width: 100, height: 32)
        window.contentView?.addSubview(text)
        window.contentView?.addSubview(screen)
        window.contentView?.addSubview(access)
        window.contentView?.addSubview(close)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboarding = window
    }

    @objc private func requestScreen() { CGRequestScreenCaptureAccess() }
    @objc private func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
    @objc private func closeOnboarding() { onboarding?.close() }
}
