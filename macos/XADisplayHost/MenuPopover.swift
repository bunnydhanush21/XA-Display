@preconcurrency import AppKit
import XADisplayProtocol

@MainActor
final class MenuPopoverController: NSObject {
    let popover = NSPopover()
    var onConnect: (() -> Void)?
    var onDisconnect: (() -> Void)?
    var onPreset: ((StreamPreset.ID) -> Void)?
    var onCustom: (() -> Void)?
    var onToggle: ((String, Bool) -> Void)?
    var onArrange: (() -> Void)?
    var onSettings: (() -> Void)?
    var onDiagnostics: (() -> Void)?
    var onQuit: (() -> Void)?
    var onFixPermissions: (() -> Void)?
    private let header = NSTextField(labelWithString: "XA Display")
    private let stats = NSTextField(labelWithString: "")
    private let connectButton = NSButton(title: "Connect", target: nil, action: nil)
    private let presets = NSSegmentedControl(labels: ["Battery", "Balanced", "Sharp"], trackingMode: .selectOne, target: nil, action: nil)
    private let permission = NSButton(title: "", target: nil, action: nil)
    private var toggles: [String: NSButton] = [:]

    override init() {
        super.init()
        popover.contentSize = NSSize(width: 320, height: 420)
        popover.behavior = .transient
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 420))
        header.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        header.frame = NSRect(x: 16, y: 378, width: 288, height: 28)
        stats.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        stats.frame = NSRect(x: 16, y: 354, width: 288, height: 20)
        connectButton.frame = NSRect(x: 16, y: 308, width: 288, height: 36)
        connectButton.bezelStyle = .rounded
        connectButton.keyEquivalent = "d"
        connectButton.target = self
        connectButton.action = #selector(connectTapped)
        presets.frame = NSRect(x: 16, y: 268, width: 200, height: 28)
        presets.target = self
        presets.action = #selector(presetTapped)
        let custom = NSButton(title: "Custom…", target: self, action: #selector(customTapped))
        custom.frame = NSRect(x: 224, y: 266, width: 80, height: 28)
        custom.bezelStyle = .rounded
        let names = [("audio", "Audio"), ("clipboard", "Clipboard"), ("touch", "Pointer"), ("latency", "Low latency")]
        for (index, item) in names.enumerated() {
            let button = NSButton(checkboxWithTitle: item.1, target: self, action: #selector(toggled(_:)))
            let column = index % 2
            let row = index / 2
            button.frame = NSRect(x: 16 + column * 150, y: 220 - row * 28, width: 140, height: 24)
            button.identifier = NSUserInterfaceItemIdentifier(item.0)
            toggles[item.0] = button
            view.addSubview(button)
        }
        permission.frame = NSRect(x: 16, y: 150, width: 288, height: 28)
        permission.bezelStyle = .rounded
        permission.target = self
        permission.action = #selector(fixTapped)
        permission.isHidden = true
        let footer = ["Arrange Displays…", "Settings…", "Diagnostics", "Quit"]
        let actions = [#selector(arrangeTapped), #selector(settingsTapped), #selector(diagnosticsTapped), #selector(quitTapped)]
        for (index, title) in footer.enumerated() {
            let button = NSButton(title: title, target: self, action: actions[index])
            button.frame = NSRect(x: 16 + (index % 2) * 150, y: 96 - (index / 2) * 32, width: 140, height: 28)
            button.bezelStyle = .rounded
            view.addSubview(button)
        }
        let note = NSTextField(wrappingLabelWithString: "Pointer events are CGEvent clicks, not native touch.")
        note.font = NSFont.systemFont(ofSize: 11)
        note.frame = NSRect(x: 16, y: 8, width: 288, height: 32)
        for item in [header, stats, connectButton, presets, custom, permission, note] { view.addSubview(item) }
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = view
    }

    func refresh(_ snapshot: MenuSnapshot) {
        XALog.write(XALog.ui, "menu refresh")
        let link = snapshot.transport.isEmpty ? "waiting" : snapshot.transport
        header.stringValue = snapshot.peerName.isEmpty ? "No iPad yet" : snapshot.peerName
        stats.stringValue = "\(link)   \(snapshot.latency)   \(snapshot.fps)"
        let live = snapshot.phase == .streaming || snapshot.phase == .pairing || snapshot.phase == .reconnecting
        connectButton.title = live ? "Disconnect" : "Connect"
        toggles["audio"]?.state = snapshot.audio ? .on : .off
        toggles["clipboard"]?.state = snapshot.clipboard ? .on : .off
        toggles["touch"]?.state = snapshot.touch ? .on : .off
        toggles["latency"]?.state = snapshot.lowLatency ? .on : .off
        if snapshot.preset == "safe" { presets.selectedSegment = 0 } else if snapshot.preset == "native" { presets.selectedSegment = 2 } else { presets.selectedSegment = 1 }
        if !snapshot.screenRecording {
            permission.title = "Screen Recording needed → Fix"
            permission.isHidden = false
        } else if !snapshot.accessibility {
            permission.title = "Accessibility needed → Fix"
            permission.isHidden = false
        } else {
            permission.isHidden = true
        }
    }

    @objc private func connectTapped() {
        if connectButton.title == "Disconnect" { onDisconnect?() } else { onConnect?() }
    }
    @objc private func presetTapped() {
        let ids: [StreamPreset.ID] = [.safe, .balanced, .native]
        let index = presets.selectedSegment
        guard index >= 0, index < ids.count else { return }
        onPreset?(ids[index])
    }
    @objc private func customTapped() { onCustom?() }
    @objc private func toggled(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        onToggle?(id, sender.state == .on)
    }
    @objc private func fixTapped() { onFixPermissions?() }
    @objc private func arrangeTapped() { onArrange?() }
    @objc private func settingsTapped() { onSettings?() }
    @objc private func diagnosticsTapped() { onDiagnostics?() }
    @objc private func quitTapped() { onQuit?() }
}

@MainActor
enum StatusGlyph {
    static func image(phase: ConnectionPhase) -> NSImage {
        let canvas = NSImage(size: NSSize(width: 22, height: 18))
        canvas.lockFocus()
        NSColor.labelColor.setStroke()
        let display = NSBezierPath(roundedRect: NSRect(x: 1, y: 3, width: 14, height: 11), xRadius: 1, yRadius: 1)
        display.lineWidth = 1.4
        display.stroke()
        let color: NSColor
        switch MenuBadge.name(for: phase) {
        case "green": color = .systemGreen
        case "yellow": color = .systemYellow
        case "red": color = .systemRed
        default: color = .systemGray
        }
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 13, y: 1, width: 7, height: 7)).fill()
        canvas.unlockFocus()
        canvas.isTemplate = false
        return canvas
    }
}
