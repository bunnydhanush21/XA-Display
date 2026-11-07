import AppKit
import ApplicationServices

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: HostController!
    private var statusItem: NSStatusItem!
    private var onboarding: NSWindow?

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
        menu.addItem(title: state, action: nil, keyEquivalent: "")
        let settings = controller.settingsSnapshot()
        menu.addItem(title: "Pairing token \(DiagnosticsText.redactToken(controller.currentToken()))", action: #selector(copyToken), keyEquivalent: "")
        menu.addItem(title: "Regenerate token", action: #selector(regenerate), keyEquivalent: "")
        addToggle(menu, "Require pairing", settings.requirePairing, #selector(togglePairing(_:)))
        addToggle(menu, "Clipboard sync", settings.clipboardSync, #selector(toggleClipboard(_:)))
        addToggle(menu, "Audio", settings.audio, #selector(toggleAudio(_:)))
        addToggle(menu, "Window snapping", settings.windowSnapping, #selector(toggleSnap(_:)))
        addToggle(menu, "Touchscreen-style gestures", settings.touchscreenGestures, #selector(toggleTouch(_:)))
        addToggle(menu, "Wi-Fi fallback", settings.wifiFallback, #selector(toggleWiFi(_:)))
        addToggle(menu, "Auto-connect on USB", settings.autoConnectUSB, #selector(toggleAuto(_:)))
        addToggle(menu, "Saved presets", settings.savedPresets, #selector(toggleSaved(_:)))
        let presets = NSMenu()
        presets.addItem(title: "Balanced 1440×1080", action: #selector(presetBalanced), keyEquivalent: "")
        presets.addItem(title: "Safe 1024×768", action: #selector(presetSafe), keyEquivalent: "")
        presets.addItem(title: "Native experimental 2048×1536", action: #selector(presetNative), keyEquivalent: "")
        presets.addItem(title: "Save current as Last", action: #selector(savePreset), keyEquivalent: "")
        let presetItem = NSMenuItem(title: "Display preset", action: nil, keyEquivalent: "")
        presetItem.submenu = presets
        menu.addItem(presetItem)
        menu.addItem(title: "Permissions…", action: #selector(showPermissions), keyEquivalent: "")
        menu.addItem(title: "Export diagnostics…", action: #selector(exportDiagnostics), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(title: "Quit XA Display Host", action: #selector(quit), keyEquivalent: "q")
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
    @objc private func toggleSnap(_ sender: NSMenuItem) { controller.setWindowSnapping(sender.state != .on) }
    @objc private func toggleTouch(_ sender: NSMenuItem) { controller.setTouchGestures(sender.state != .on) }
    @objc private func toggleWiFi(_ sender: NSMenuItem) { controller.setWiFi(sender.state != .on) }
    @objc private func toggleAuto(_ sender: NSMenuItem) { controller.setAutoConnect(sender.state != .on) }
    @objc private func toggleSaved(_ sender: NSMenuItem) { controller.setSavedPresets(sender.state != .on) }
    @objc private func presetBalanced() { controller.selectPreset(.balanced) }
    @objc private func presetSafe() { controller.selectPreset(.safe) }
    @objc private func presetNative() { controller.selectPreset(.native) }
    @objc private func savePreset() { controller.saveNamedPreset("Last") }
    @objc private func showPermissions() { showOnboarding() }
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
        let text = NSTextField(wrappingLabelWithString: """
        XA Display Host creates a virtual display and injects pointer and keyboard events. Those events are CGEvent mouse and keyboard events. They are not native Mac touchscreen input.

        Grant Screen Recording so this app can capture only the XA Display. Grant Accessibility so pointer, keyboard, and window recovery can work. Quit and reopen after granting Screen Recording if capture stays denied.

        USB is preferred. Wi-Fi is used only when the cable is gone and Wi-Fi fallback is enabled. Only a paired iPad can control the Mac while Require pairing is on.
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
