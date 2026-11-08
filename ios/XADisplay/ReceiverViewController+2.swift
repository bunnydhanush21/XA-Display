import AVFoundation
import UIKit
import XADisplayProtocol

extension ReceiverViewController {
    func wireSidebar() {
        sidebar.onToggle = { [weak self] mask in
            guard let self = self else { return }
            let down = !self.heldModifiers.contains(mask)
            if down { self.heldModifiers.insert(mask) } else { self.heldModifiers.remove(mask) }
            self.sidebar.setModifier(mask, on: down)
            self.input.send(intent: .modifier(mask, down: down))
        }
        sidebar.onEsc = { [weak self] in self?.sendShortcut(KeyShortcut(input: "\u{1b}", modifiers: [])) }
        sidebar.onUndo = { [weak self] in self?.sendShortcut(KeyShortcut(input: "z", modifiers: .command)) }
        sidebar.onRedo = { [weak self] in self?.sendShortcut(KeyShortcut(input: "z", modifiers: [.command, .shift])) }
        sidebar.onKeyboard = { [weak self] in self?.toggleKeyboard() }
        sidebar.onDisconnect = { [weak self] in self?.userDisconnect() }
        sidebar.onSettings = { [weak self] in self?.showSettings() }
        sidebar.onPrecision = { [weak self] in
            guard let self = self else { return }
            self.features.precisionMode.toggle()
            self.precisionLabel.isHidden = !self.features.precisionMode
            LocalSettings.save(token: self.token, features: self.features)
        }
        sidebar.onTrackpad = { [weak self] in
            guard let self = self else { return }
            self.features.trackpadMode.toggle()
            LocalSettings.save(token: self.token, features: self.features)
            self.statusLabel.text = self.features.trackpadMode ? "Trackpad mode sends pointer moves" : self.statusLabel.text
        }
        sidebar.onCollapse = { [weak self] in
            self?.collapsed.toggle()
            self?.applyChrome()
        }
        sidebar.onMacs = { [weak self] in self?.showMacPicker() }
        sidebar.onMedia = { [weak self] in self?.showMediaRemote() }
    }
    func applyLaunchRoute() {
        switch LaunchRoute.decide(oneTap: features.oneTapReconnect, directory: directory) {
        case .resume(let mac):
            token = mac.token
            statusLabel.text = "Connecting to \(mac.name)"
            if features.oneTapReconnect { macBrowser.poke(name: mac.name) }
        case .picker:
            statusLabel.text = "Choose a Mac"
        case .listen:
            break
        }
    }
    func showMacPicker() {
        guard features.rememberMacs || features.oneTapReconnect else { return }
        let picker = MacPickerViewController(style: .grouped)
        picker.saved = directory.sorted()
        picker.discovered = discoveredMacs
        picker.onSelectSaved = { [weak self] mac in
            guard let self = self else { return }
            self.directory.select(mac.id, now: Date().timeIntervalSince1970)
            self.adoptToken(mac.token)
            LocalSettings.saveMacs(self.directory)
            LocalSettings.save(token: mac.token, features: self.features)
            self.statusLabel.text = "Connecting to \(mac.name)"
            self.statusLabel.isHidden = false
            self.macBrowser.poke(name: mac.name)
            self.input.ensureListening()
            self.receiver.ensureListening()
        }
        picker.onSelectDiscovered = { [weak self] name in
            guard let self = self else { return }
            let existing = self.directory.macs.first { $0.id == name }
            let mac = SavedMac(id: name, name: name, token: existing?.token ?? self.token, lastUsed: Date().timeIntervalSince1970)
            self.directory.remember(mac)
            self.adoptToken(mac.token)
            LocalSettings.saveMacs(self.directory)
            LocalSettings.save(token: mac.token, features: self.features)
            self.statusLabel.text = "Connecting to \(name)"
            self.statusLabel.isHidden = false
            self.macBrowser.poke(name: name)
        }
        present(UINavigationController(rootViewController: picker), animated: true)
    }
    func showMediaRemote() {
        guard features.mediaRemote else { return }
        let panel = MediaRemoteViewController()
        panel.modalPresentationStyle = .fullScreen
        panel.onCommand = { [weak self] action, scrub in
            self?.input.sendMedia(action, scrub: scrub)
        }
        panel.onClose = { [weak self] in
            self?.mediaPanel = nil
            self?.dismiss(animated: true)
        }
        mediaPanel = panel
        present(panel, animated: true)
    }
    func rememberConnectedMac() {
        guard features.rememberMacs else { return }
        let name = directory.last()?.name ?? discoveredMacs.first ?? "Mac"
        let id = directory.last()?.id ?? name
        directory.remember(SavedMac(id: id, name: name, token: token, lastUsed: Date().timeIntervalSince1970))
        LocalSettings.saveMacs(directory)
    }
    func command(_ item: CommandStripItem) {
        guard features.commandStrip else { return }
        if let action = item.windowAction {
            guard features.windowSnapping || features.touchscreenGestures else { return }
            input.sendWindow(action)
            return
        }
        sendShortcut(KeyShortcut(input: item.input, modifiers: XAModifierMask(rawValue: item.modifiers)))
    }
    func sendShortcut(_ shortcut: KeyShortcut) {
        for intent in shortcut.intents() { input.send(intent: intent) }
    }
    func sendSnap(_ zone: SnapZone) {
        guard features.windowSnapping || features.touchscreenGestures else { return }
        switch zone {
        case .leftHalf: input.sendWindow(.snapLeft)
        case .rightHalf: input.sendWindow(.snapRight)
        case .full: input.sendWindow(.fill)
        case .mainDisplay: input.sendWindow(.moveToMain)
        }
    }
    func toggleKeyboard() {
        guard settingsDocument.keyboardEnabled else { return }
        keyboardOn.toggle()
        if keyboardOn {
            keyInput.becomeFirstResponder()
        } else {
            keyInput.resignFirstResponder()
            becomeFirstResponder()
        }
    }
    func userDisconnect() {
        userPaused = true
        input.sendRelease()
        input.pause()
        receiver.pause()
        UIApplication.shared.isIdleTimerDisabled = false
        releaseModifiers()
        statusLabel.text = "Disconnected"
        statusLabel.isHidden = false
    }
    func showSettings() {
        settingsDocument.features = features
        settingsDocument.assist = assist
        settingsDocument.pairedIDs = directory.sorted().map(\.name)
        let settings = SettingsViewController(document: settingsDocument, token: token)
        settings.onRestoreCharging = { [weak self] in self?.batteryLoop.restore() }
        settings.onDisableBatteryCare = { [weak self] in self?.batteryLoop.disable() }
        settings.onDiagnostics = { [weak self] in self?.copyDiagnostics() }
        settings.onRevoke = { [weak self] in
            guard let self = self else { return }
            self.directory = MacDirectory()
            LocalSettings.saveMacs(self.directory)
            self.adoptToken("")
        }
        settings.onLive = { [weak self] document, token in
            self?.apply(document: document, token: token, broadcast: true)
        }
        present(UINavigationController(rootViewController: settings), animated: true)
    }
    func apply(document: XASettingsDocument, token: String, broadcast: Bool) {
        let previous = SettingsSync.encode(settingsDocument)
        settingsDocument = document
        features = document.features
        assist = document.assist
        chargeConfig = document.charge
        adoptToken(token)
        input.requirePairing = features.requirePairing
        clipboard.enabled = features.clipboardSync
        precisionLabel.isHidden = !features.precisionMode
        if features.audio { audio.start() } else { audio.stop() }
        audio.volume = document.audioVolume
        collapsed = !document.sidebarVisible
        scrollRecognizer?.isEnabled = document.twoFingerScroll
        receiver.lowLatency = document.features.lowLatencyWiFi
        updateKeepalive()
        LocalSettings.save(token: token, features: features)
        LocalSettings.saveDocument(document)
        applyChrome()
        if features.oneTapReconnect || features.rememberMacs { macBrowser.start() } else { macBrowser.stop() }
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        interpreter = DirectTouchInterpreter(
            slop: features.gestureTuning.clamped().slop,
            doubleTapWindow: features.gestureTuning.clamped().doubleTapWindow,
            longPressDuration: features.gestureTuning.clamped().longPressDuration
        )
        titleArbiter = TitleBarArbiter(window: features.gestureTuning.clamped().doubleTapWindow)
        if broadcast, SettingsSync.encode(document) != previous {
            receiver.sendSettings(SettingsSync.encode(document))
        }
        view.setNeedsLayout()
    }
    func updateKeepalive() {
        keepalive?.invalidate()
        keepalive = nil
        guard features.lowLatencyWiFi, receiver.isConnected else { return }
        keepalive = Timer.scheduledTimer(withTimeInterval: WiFiPowerSave.keepaliveSeconds, repeats: true) { [weak self] _ in
            self?.input.sendPing()
        }
    }
    func copyDiagnostics() {
        UIPasteboard.general.string = DiagnosticsCopy.text(
            features: features, token: token, transport: streamLabel, preset: settingsDocument.preset,
            thermal: ThermalBucket.from(processInfoRawValue: ProcessInfo.processInfo.thermalState.rawValue).rawValue,
            battery: batteryLoop.lastText, notes: ["settings"]
        )
    }
    func adoptToken(_ value: String) {
        token = value
        input.token = value
        receiver?.setPairingToken(value)
    }

    func installConnectionChrome() {
        connectionOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(connectionOverlay)
        NSLayoutConstraint.activate([
            connectionOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            connectionOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            connectionOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            connectionOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        connectionOverlay.onConnect = { [weak self] code in
            guard let self = self else { return }
            self.adoptToken(code.trimmingCharacters(in: .whitespacesAndNewlines))
            LocalSettings.save(token: self.token, features: self.features)
            self.sendAuth()
            XALog.write(XALog.ui, "pairing code saved")
        }
        connectionOverlay.onSettings = { [weak self] in self?.showSettings() }
        connectionOverlay.show(macs: directory.sorted().map(\.name), code: token)
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        pill.textColor = .white
        pill.backgroundColor = UIColor(white: 0, alpha: 0.55)
        pill.textAlignment = .center
        pill.layer.cornerRadius = 11
        pill.clipsToBounds = true
        pill.isHidden = true
        view.addSubview(pill)
        NSLayoutConstraint.activate([
            pill.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            pill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pill.heightAnchor.constraint(equalToConstant: 22),
            pill.widthAnchor.constraint(lessThanOrEqualToConstant: 280)
        ])
    }
    func sendAuth() {
        guard !token.isEmpty else { return }
        receiver.sendAuth(id: VideoReceiver.installID, token: token)
    }
    @objc func showPill() {
        guard StatsPill.heightFits(pill: 22, screen: Double(view.bounds.height)) else { return }
        let latency = pipelineMs.map { String(format: "%.0f ms", $0) } ?? "—"
        pill.text = "  \(latency) · \(String(format: "%.0f", fps)) fps · \(streamLabel)  "
        pill.isHidden = false
        pillTimer?.invalidate()
        let interval = UIAccessibility.isReduceMotionEnabled ? 0.0 : 0.2
        UIView.animate(withDuration: interval) { self.pill.alpha = 1 }
        pillTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            self?.pill.isHidden = true
        }
    }
    func applyChrome() {
        sidebarWidth.constant = collapsed ? 20 : 96
        sidebar.setCollapsed(collapsed)
        sidebarLeading.isActive = features.gestureTuning.sidebarOnLeft
        sidebarTrailing.isActive = !features.gestureTuning.sidebarOnLeft
        sidebar.setShowsMedia(features.mediaRemote)
        commandStrip.isHidden = !features.commandStrip
        commandStripHeight.constant = assist.largeButtons ? 68 : 52
        sidebar.setLarge(assist.largeButtons)
        chrome.setLarge(assist.largeButtons)
        chrome.layout(windows: windowFrames.map { self.viewRect(for: $0) }, assist: assist)
        statsLabel.isHidden = !features.showStats
        precisionLabel.isHidden = !features.precisionMode
        sidebarEdge?.isEnabled = features.gestureTuning.sidebarOnLeft
        drawerEdge?.isEnabled = assist.edgeDrawer
    }
}
