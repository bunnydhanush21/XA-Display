@preconcurrency import AppKit
import XADisplayProtocol

@MainActor
final class HostSettingsPanel: NSObject {
    let window: NSWindow
    var onChange: ((XASettingsDocument) -> Void)?
    var onRevoke: (() -> Void)?
    var onDiagnostics: (() -> Void)?
    var onScreen: (() -> Void)?
    var onAccessibility: (() -> Void)?
    var apps: [(bundle: String, name: String)] = []
    var selectedBundles: [String] = []
    var onToggleApp: ((String) -> Void)?
    private var document: XASettingsDocument
    private let tabs = NSTabView(frame: NSRect(x: 12, y: 12, width: 616, height: 440))

    init(document: XASettingsDocument) {
        self.document = document
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = "XA Display Settings"
        window.contentView?.addSubview(tabs)
        rebuild()
        window.center()
    }

    func update(_ document: XASettingsDocument) {
        self.document = document
        rebuild()
    }

    func select(tab title: String) {
        guard let item = tabs.tabViewItems.first(where: { $0.label == title }) else { return }
        tabs.selectTabViewItem(item)
    }

    private func rebuild() {
        tabs.tabViewItems.forEach { tabs.removeTabViewItem($0) }
        for tab in SettingsCatalog.hostTabs {
            let view = NSView(frame: tabs.contentRect)
            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 8
            stack.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16)
            ])
            for section in tab.sections {
                for row in SettingsCatalog.rows(in: section, host: true) {
                    stack.addArrangedSubview(control(for: row))
                    stack.addArrangedSubview(NSTextField(labelWithString: rowNote(row)))
                }
            }
            if tab.sections.contains("Audio"), document.audioMode == AudioRouteMode.selected.rawValue {
                for app in apps.prefix(24) where !app.bundle.isEmpty {
                    let button = NSButton(checkboxWithTitle: app.name.isEmpty ? app.bundle : app.name, target: self, action: #selector(toggledApp(_:)))
                    button.identifier = NSUserInterfaceItemIdentifier("app:" + app.bundle)
                    button.state = selectedBundles.contains(app.bundle) ? .on : .off
                    stack.addArrangedSubview(button)
                }
            }
            let item = NSTabViewItem(identifier: tab.title)
            item.label = tab.title
            item.view = view
            tabs.addTabViewItem(item)
        }
    }

    private func rowNote(_ row: SettingsRow) -> String {
        switch row.id {
        case "display.width", "display.height", "display.fps", "display.bitrate", "display.custom":
            return "Applies live. The virtual display is recreated."
        case "connection.login":
            return "Uses the system login item. An unsigned build may be refused by macOS."
        case "display.preset":
            return "Battery is Safe, Balanced is the default, Sharp is the experimental Native preset."
        default:
            return "Applies live."
        }
    }

    private func control(for row: SettingsRow) -> NSView {
        let value = document.value(for: row.id)
        switch row.kind {
        case "toggle":
            let button = NSButton(checkboxWithTitle: row.title, target: self, action: #selector(toggled(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(row.id)
            if case .bool(let on) = value { button.state = on ? .on : .off }
            return button
        case "choice":
            let popup = NSPopUpButton()
            popup.identifier = NSUserInterfaceItemIdentifier(row.id)
            popup.addItems(withTitles: row.choices.isEmpty ? [valueText(value)] : row.choices)
            if case .choice(let choice) = value { popup.selectItem(withTitle: choice) }
            popup.target = self
            popup.action = #selector(chose(_:))
            let label = NSTextField(labelWithString: row.title)
            let stack = NSStackView(views: [label, popup])
            stack.orientation = .horizontal
            return stack
        case "slider":
            let slider = NSSlider(value: 0, minValue: row.minimum, maxValue: row.maximum, target: self, action: #selector(slid(_:)))
            slider.identifier = NSUserInterfaceItemIdentifier(row.id)
            if case .number(let number) = value { slider.doubleValue = number }
            slider.widthAnchor.constraint(equalToConstant: 220).isActive = true
            let label = NSTextField(labelWithString: row.title)
            let stack = NSStackView(views: [label, slider])
            stack.orientation = .horizontal
            return stack
        case "action":
            let button = NSButton(title: row.title, target: self, action: #selector(acted(_:)))
            button.bezelStyle = .rounded
            button.identifier = NSUserInterfaceItemIdentifier(row.id)
            return button
        default:
            return NSTextField(labelWithString: row.title + ": " + valueText(value))
        }
    }

    private func valueText(_ value: SettingValue) -> String {
        switch value {
        case .bool(let on): return on ? "On" : "Off"
        case .number(let number): return String(format: "%.2f", number)
        case .choice(let choice): return choice
        }
    }

    @objc private func toggled(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        document.set(.bool(sender.state == .on), for: id)
        onChange?(document)
    }

    @objc private func chose(_ sender: NSPopUpButton) {
        guard let id = sender.identifier?.rawValue, let title = sender.titleOfSelectedItem else { return }
        document.set(.choice(title), for: id)
        onChange?(document)
    }

    @objc private func slid(_ sender: NSSlider) {
        guard let id = sender.identifier?.rawValue else { return }
        document.set(.number(sender.doubleValue), for: id)
        onChange?(document)
    }

    @objc private func toggledApp(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, id.hasPrefix("app:") else { return }
        onToggleApp?(String(id.dropFirst(4)))
    }

    @objc private func acted(_ sender: NSButton) {
        switch sender.identifier?.rawValue {
        case "security.revoke": onRevoke?()
        case "permissions.screen": onScreen?()
        case "permissions.access": onAccessibility?()
        case "about.diagnostics": onDiagnostics?()
        case "about.reset":
            document.reset()
            rebuild()
            onChange?(document)
        default: break
        }
    }
}
