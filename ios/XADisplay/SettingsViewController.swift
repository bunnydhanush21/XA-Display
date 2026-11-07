import UIKit
import XADisplayProtocol

final class SettingsViewController: UITableViewController {
    var features: XAFeatureSettings
    var token: String
    var onChange: ((XAFeatureSettings, String) -> Void)?
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
    ]

    init(features: XAFeatureSettings, token: String) {
        self.features = features
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
        onChange?(features, tokenField.text ?? "")
        dismiss(animated: true)
    }

    @objc private func tokenChanged() {
        token = tokenField.text ?? ""
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : (section == 1 ? rows.count : 5)
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 2 {
            return "Pointer events are mouse and keyboard events on the Mac, not native touch input. The slider is iPad playback volume. Audio stays off until you enable it here and in XA Display Host. The host chooses all audio, selected apps, or apps on the iPad display. Mute-on-Mac is not available."
        }
        if section == 0 { return "Type the token shown in the Mac menu bar." }
        return nil
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["Pairing", "Features", "About"][section]
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
        if indexPath.section == 2 && indexPath.row == 0 {
            UIPasteboard.general.string = DiagnosticsCopy.text(
                features: features, token: token, transport: "see main screen", preset: "see main screen",
                thermal: ThermalBucket.from(processInfoRawValue: ProcessInfo.processInfo.thermalState.rawValue).rawValue,
                battery: batteryText(), notes: ["settings"]
            )
        } else if indexPath.section == 2 && indexPath.row == 1 {
            let order = [0, 90, 180, 270]
            let next = order.firstIndex(of: features.inputRotation).map { order[($0 + 1) % order.count] } ?? 0
            features.inputRotation = next
            tableView.reloadRows(at: [indexPath], with: .none)
        } else if indexPath.section == 2 && indexPath.row == 2 {
            let order = [8.0, 12.0, 20.0, 32.0]
            let next = order.firstIndex(of: features.gestureTuning.slop).map { order[($0 + 1) % order.count] } ?? order[0]
            features.gestureTuning.slop = next
            tableView.reloadRows(at: [indexPath], with: .none)
        } else if indexPath.section == 2 && indexPath.row == 3 {
            let order = [0.25, 0.35, 0.5]
            let next = order.firstIndex(of: features.gestureTuning.doubleTapWindow).map { order[($0 + 1) % order.count] } ?? order[0]
            features.gestureTuning.doubleTapWindow = next
            tableView.reloadRows(at: [indexPath], with: .none)
        } else if indexPath.section == 2 {
            let order = [0.35, 0.45, 0.7]
            let next = order.firstIndex(of: features.gestureTuning.longPressDuration).map { order[($0 + 1) % order.count] } ?? order[0]
            features.gestureTuning.longPressDuration = next
            tableView.reloadRows(at: [indexPath], with: .none)
        }
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
