import UIKit
import XADisplayProtocol

final class SettingsViewController: UITableViewController {
    var features: XAFeatureSettings
    var assist: TouchAssist
    var token: String
    var onChange: ((XAFeatureSettings, TouchAssist, String) -> Void)?
    var onRestoreCharging: (() -> Void)?
    var onDisableBatteryCare: (() -> Void)?
    private let tokenField = UITextField()
    private let rows: [(String, WritableKeyPath<XAFeatureSettings, Bool>)] = [
        ("Require pairing", \.requirePairing),
        ("Clipboard sync", \.clipboardSync),
        ("Three-finger shortcuts", \.threeFingerShortcuts),
        ("Pinch magnifier", \.pinchMagnifier),
        ("Command strip", \.commandStrip),
        ("Window snapping", \.windowSnapping),
        ("Audio", \.audio),
        ("Sidebar on the left", \.gestureTuning.sidebarOnLeft),
        ("Touchscreen-style gestures", \.touchscreenGestures),
        ("Trackpad mode", \.trackpadMode),
        ("Momentum scroll", \.scrollInertia),
        ("Stats overlay", \.showStats),
        ("Precision overlay", \.precisionMode),
        ("One-tap reconnect", \.oneTapReconnect),
        ("Remember Macs", \.rememberMacs),
        ("Media remote", \.mediaRemote),
        ("Battery telemetry", \.batteryTelemetry),
        ("Charge limit (experimental)", \.chargeLimit)
    ]

    init(features: XAFeatureSettings, assist: TouchAssist, token: String) {
        self.features = features
        self.assist = assist
        self.token = token
        super.init(style: .grouped)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "XA Display"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(done))
        tokenField.text = token
        tokenField.autocapitalizationType = .allCharacters
        tokenField.autocorrectionType = .no
        tokenField.placeholder = "Pairing token"
        tokenField.borderStyle = .roundedRect
        tokenField.addTarget(self, action: #selector(tokenChanged), for: .editingChanged)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        let header = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 64))
        let slider = UISlider(frame: CGRect(x: 20, y: 20, width: 280, height: 32))
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.value = Float(UserDefaults.standard.object(forKey: "XADisplay.audioVolume") as? Double ?? 1)
        slider.addTarget(self, action: #selector(volumeChanged(_:)), for: .valueChanged)
        header.addSubview(slider)
        tableView.tableHeaderView = header
    }

    @objc private func volumeChanged(_ sender: UISlider) {
        UserDefaults.standard.set(Double(sender.value), forKey: "XADisplay.audioVolume")
    }

    @objc private func done() {
        onChange?(features, assist, tokenField.text ?? "")
        dismiss(animated: true)
    }

    @objc private func tokenChanged() {
        token = tokenField.text ?? ""
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 5 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1
        case 1: return rows.count
        case 2: return 10
        case 3: return 5
        default: return 2
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 3 {
            return
                "Pointer events are mouse and keyboard events on the Mac, not native touch input. The slider is iPad playback volume. Audio stays off until you enable it here and in XA Display Host. The host chooses all audio, selected apps, or apps on the iPad display. Mute-on-Mac is not available."
        }
        if section == 2 {
            return
                "Title-bar double-tap fills or restores that window. A double-tap in the window contents stays a click. Flicks tile only from the title bar. Notification Center and Control Center use Accessibility menu extras unless you set a key here. Mission Control is Control-Up, App Exposé is Control-Down, and Apps is F4. Hold duration and movement threshold are the long-press and tap slop rows in About. Hit targets stay at least 36 points."
        }
        if section == 4 {
            return
                "Charge limit is experimental and off until you enable it. It needs the separate root helper in jailbreak/battery-care. Prove stop and resume on a device (see docs/TESTING.md) before leaving it on. DisableInflow and ExternalConnected are not used. Heat lowers brightness and stream rate. It does not change Apple thermal controls."
        }
        if section == 0 { return "Type the token shown in the Mac menu bar." }
        return nil
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["Pairing", "Features", "Touch", "About", "Battery care"][section]
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.selectionStyle = .none
        cell.accessoryView = nil
        cell.textLabel?.numberOfLines = 2
        if indexPath.section == 0 {
            cell.textLabel?.text = nil
            tokenField.frame = CGRect(x: 16, y: 6, width: tableView.bounds.width - 32, height: 36)
            cell.contentView.addSubview(tokenField)
            return cell
        }
        if indexPath.section == 2 {
            cell.textLabel?.text = touchTitle(indexPath.row)
            if indexPath.row < 6 {
                let toggle = UISwitch()
                toggle.isOn = touchOn(indexPath.row)
                toggle.tag = indexPath.row
                toggle.addTarget(self, action: #selector(touchToggled(_:)), for: .valueChanged)
                cell.accessoryView = toggle
            } else {
                cell.selectionStyle = .default
            }
            return cell
        }
        if indexPath.section == 4 {
            cell.textLabel?.text = indexPath.row == 0 ? "Restore normal charging" : "Disable battery care"
            cell.selectionStyle = .default
            return cell
        }
        if indexPath.section == 3 {
            switch indexPath.row {
            case 0: cell.textLabel?.text = "Copy diagnostics"
            case 1: cell.textLabel?.text = "Input rotation \(features.inputRotation)°"
            case 2: cell.textLabel?.text = String(format: "Tap slop %.0f pt", features.gestureTuning.slop)
            case 3: cell.textLabel?.text = String(format: "Double-tap %.2f s", features.gestureTuning.doubleTapWindow)
            default: cell.textLabel?.text = String(format: "Long-press %.2f s", features.gestureTuning.longPressDuration)
            }
            cell.accessoryView = nil
            cell.selectionStyle = .default
            return cell
        }
        let row = rows[indexPath.row]
        cell.textLabel?.text = row.0
        let toggle = UISwitch()
        toggle.isOn = features[keyPath: row.1]
        toggle.tag = indexPath.row
        toggle.addTarget(self, action: #selector(toggled(_:)), for: .valueChanged)
        cell.accessoryView = toggle
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 4 {
            if indexPath.row == 0 { onRestoreCharging?() } else { onDisableBatteryCare?() }
            return
        }
        if indexPath.section == 2 {
            guard indexPath.row >= 6 else { return }
            cycleTouch(indexPath.row)
            tableView.reloadRows(at: [indexPath], with: .none)
            return
        }
        if indexPath.section == 3 && indexPath.row == 0 {
            UIPasteboard.general.string = DiagnosticsCopy.text(
                features: features, token: token, transport: "see main screen", preset: "see main screen",
                thermal: ThermalBucket.from(processInfoRawValue: ProcessInfo.processInfo.thermalState.rawValue).rawValue,
                battery: batteryText(), notes: ["settings"]
            )
        } else if indexPath.section == 3 && indexPath.row == 1 {
            let order = [0, 90, 180, 270]
            let next = order.firstIndex(of: features.inputRotation).map { order[($0 + 1) % order.count] } ?? 0
            features.inputRotation = next
            tableView.reloadRows(at: [indexPath], with: .none)
        } else if indexPath.section == 3 && indexPath.row == 2 {
            let order = [8.0, 12.0, 20.0, 32.0]
            let next = order.firstIndex(of: features.gestureTuning.slop).map { order[($0 + 1) % order.count] } ?? order[0]
            features.gestureTuning.slop = next
            tableView.reloadRows(at: [indexPath], with: .none)
        } else if indexPath.section == 3 && indexPath.row == 3 {
            let order = [0.25, 0.35, 0.5]
            let next = order.firstIndex(of: features.gestureTuning.doubleTapWindow).map { order[($0 + 1) % order.count] } ?? order[0]
            features.gestureTuning.doubleTapWindow = next
            tableView.reloadRows(at: [indexPath], with: .none)
        } else if indexPath.section == 3 {
            let order = [0.35, 0.45, 0.7]
            let next = order.firstIndex(of: features.gestureTuning.longPressDuration).map { order[($0 + 1) % order.count] } ?? order[0]
            features.gestureTuning.longPressDuration = next
            tableView.reloadRows(at: [indexPath], with: .none)
        }
    }

    @objc private func touchToggled(_ sender: UISwitch) {
        switch sender.tag {
        case 0: assist.windowChrome = sender.isOn
        case 1: assist.loupeWhileDragging = sender.isOn
        case 2: assist.trafficLights = sender.isOn
        case 3: assist.menuOverlay = sender.isOn
        case 4: assist.edgeDrawer = sender.isOn
        default: assist.largeButtons = sender.isOn
        }
    }

    private func touchOn(_ row: Int) -> Bool {
        switch row {
        case 0: return assist.windowChrome
        case 1: return assist.loupeWhileDragging
        case 2: return assist.trafficLights
        case 3: return assist.menuOverlay
        case 4: return assist.edgeDrawer
        default: return assist.largeButtons
        }
    }

    private func touchTitle(_ row: Int) -> String {
        switch row {
        case 0: return "Window title actions"
        case 1: return "Loupe while dragging"
        case 2: return "Traffic-light buttons"
        case 3: return "Large menu overlay"
        case 4: return "Right-edge action drawer"
        case 5: return "Large buttons"
        case 6: return String(format: "Cursor offset %.0f, %.0f", assist.cursorOffsetX, assist.cursorOffsetY)
        case 7: return String(format: "Ignore repeat %.2f s", assist.ignoreRepeat)
        case 8: return "Notification Center: \(edgeLabel(.notificationCenter))"
        default: return "Control Center: \(edgeLabel(.controlCenter))"
        }
    }

    private func edgeLabel(_ action: EdgeSystemAction) -> String {
        let binding = assist.binding(for: action)
        if binding.input.isEmpty { return "Accessibility" }
        return "\(binding.input) modifiers \(binding.modifiers)"
    }

    private func cycleTouch(_ row: Int) {
        switch row {
        case 6:
            let order = [0.0, -24.0, -36.0]
            let next = order.firstIndex(of: assist.cursorOffsetY).map { order[($0 + 1) % order.count] } ?? -24
            assist.cursorOffsetY = next
            assist.cursorOffsetX = 0
        case 7:
            let order = [0.0, 0.28, 0.5]
            assist.ignoreRepeat = order.firstIndex(of: assist.ignoreRepeat).map { order[($0 + 1) % order.count] } ?? 0.28
        case 8:
            cycleEdge(.notificationCenter)
        case 9:
            cycleEdge(.controlCenter)
        default:
            break
        }
    }

    private func cycleEdge(_ action: EdgeSystemAction) {
        let choices: [(String, UInt8)] = [("", 0), ("n", XAModifierMask.option.rawValue), ("n", XAModifierMask.option.rawValue | XAModifierMask.command.rawValue)]
        var bindings = assist.edgeBindings
        if bindings.isEmpty { bindings = TouchAssist.defaultEdges }
        let current = bindings.firstIndex { $0.action == action } ?? 0
        let now = assist.binding(for: action)
        let next = choices.firstIndex { $0.0 == now.input && $0.1 == now.modifiers }.map { choices[($0 + 1) % choices.count] } ?? choices[0]
        let updated = EdgeBinding(action: action, input: next.0, modifiers: next.1)
        if bindings.contains(where: { $0.action == action }) {
            bindings = bindings.map { $0.action == action ? updated : $0 }
        } else {
            bindings.append(updated)
        }
        assist.edgeBindings = bindings
    }

    @objc private func toggled(_ sender: UISwitch) {
        let row = rows[sender.tag]
        features[keyPath: row.1] = sender.isOn
    }

    private func batteryText() -> String {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        if level < 0 { return "unknown" }
        return "\(Int(level * 100))%"
    }
}
