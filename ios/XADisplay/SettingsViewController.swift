import UIKit
import XADisplayProtocol

final class SettingsViewController: UITableViewController {
    var document: XASettingsDocument
    var token: String
    var onLive: ((XASettingsDocument, String) -> Void)?
    var onDiagnostics: (() -> Void)?
    var onRevoke: (() -> Void)?
    var onRestoreCharging: (() -> Void)?
    var onDisableBatteryCare: (() -> Void)?
    private let sections = SettingsCatalog.sections(host: false)

    init(document: XASettingsDocument, token: String) {
        self.document = document
        self.token = token
        super.init(style: .grouped)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(done))
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    @objc private func done() { dismiss(animated: true) }

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        SettingsCatalog.rows(in: sections[section], host: false).count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section] }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch sections[section] {
        case "Display":
            return "Custom width, height, frame rate, and bitrate apply when Custom display is on. The Mac recreates the virtual display. Presets remain the default."
        case "Battery care":
            return "Telemetry is read-only. Charge limit is experimental and off until the device test in docs/TESTING.md passes. The helper never writes DisableInflow or ExternalConnected."
        case "Security":
            return "Revoke clears the saved Mac token on this iPad. The Mac token changes only from the host."
        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        row(indexPath).kind == "slider" ? 74 : 48
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        cell.accessoryView = nil
        cell.selectionStyle = .none
        cell.textLabel?.text = nil
        let item = row(indexPath)
        let title = UILabel(frame: CGRect(x: 16, y: 8, width: tableView.bounds.width - 180, height: 32))
        title.font = UIFont.systemFont(ofSize: 16)
        title.text = item.title
        title.numberOfLines = 2
        cell.contentView.addSubview(title)
        let value = document.value(for: item.id)
        switch item.kind {
        case "toggle":
            let toggle = UISwitch()
            if case .bool(let on) = value { toggle.isOn = on }
            toggle.tag = tag(indexPath)
            toggle.addTarget(self, action: #selector(toggled(_:)), for: .valueChanged)
            cell.accessoryView = toggle
        case "choice":
            let control = UISegmentedControl(items: item.choices)
            control.frame = CGRect(x: 16, y: 36, width: max(160, tableView.bounds.width - 32), height: 28)
            if case .choice(let choice) = value, let index = item.choices.firstIndex(of: choice) { control.selectedSegmentIndex = index }
            control.tag = tag(indexPath)
            control.addTarget(self, action: #selector(chose(_:)), for: .valueChanged)
            if item.id == "display.detail" || item.id == "security.devices" {
                title.text = item.title + ": " + (valueText(value))
            } else {
                title.frame.size.height = 20
                cell.contentView.addSubview(control)
            }
        case "slider":
            let slider = UISlider(frame: CGRect(x: 16, y: 36, width: tableView.bounds.width - 32, height: 28))
            slider.minimumValue = Float(item.minimum)
            slider.maximumValue = Float(item.maximum)
            if case .number(let number) = value { slider.value = Float(number) }
            slider.tag = tag(indexPath)
            slider.addTarget(self, action: #selector(slid(_:)), for: .valueChanged)
            title.text = item.title + " " + valueText(value)
            cell.contentView.addSubview(slider)
        case "action":
            cell.selectionStyle = .default
            cell.accessoryType = .disclosureIndicator
        default:
            title.text = item.title + ": " + valueText(value)
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch row(indexPath).id {
        case "about.diagnostics": onDiagnostics?()
        case "about.reset":
            document.reset()
            publish()
            tableView.reloadData()
        case "security.revoke": onRevoke?()
        case "battery.restore": onRestoreCharging?()
        case "battery.disable":
            document.set(.bool(false), for: "battery.limit")
            publish()
            onDisableBatteryCare?()
            tableView.reloadData()
        default: break
        }
    }

    private func row(_ indexPath: IndexPath) -> SettingsRow {
        SettingsCatalog.rows(in: sections[indexPath.section], host: false)[indexPath.row]
    }

    private func tag(_ indexPath: IndexPath) -> Int { indexPath.section * 100 + indexPath.row }

    private func indexPath(for tag: Int) -> IndexPath { IndexPath(row: tag % 100, section: tag / 100) }

    private func valueText(_ value: SettingValue) -> String {
        switch value {
        case .bool(let on): return on ? "On" : "Off"
        case .number(let number): return String(format: "%.2f", number)
        case .choice(let choice): return choice
        }
    }

    @objc private func toggled(_ sender: UISwitch) {
        document.set(.bool(sender.isOn), for: row(indexPath(for: sender.tag)).id)
        publish()
    }

    @objc private func chose(_ sender: UISegmentedControl) {
        let item = row(indexPath(for: sender.tag))
        guard sender.selectedSegmentIndex >= 0, sender.selectedSegmentIndex < item.choices.count else { return }
        document.set(.choice(item.choices[sender.selectedSegmentIndex]), for: item.id)
        publish()
    }

    @objc private func slid(_ sender: UISlider) {
        document.set(.number(Double(sender.value)), for: row(indexPath(for: sender.tag)).id)
        publish()
    }

    private func publish() { onLive?(document, token) }
}
