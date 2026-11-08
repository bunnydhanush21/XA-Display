import UIKit
import XADisplayProtocol

final class FirstRunController: UIViewController {
    var onFinish: (() -> Void)?
    private var step = 0
    private let titleLabel = UILabel()
    private let body = UILabel()
    private let cards = [
        ("XA Display", "This iPad becomes an extra Mac display. Touches move the Mac pointer. They are not native Mac touch."),
        ("Connect", "Plug in a data cable, or join the same Wi-Fi as the Mac. Open XA Display Host on the Mac."),
        ("Pair", "Enter the pairing code shown on the Mac. Video, audio, and clipboard stay closed until that code matches.")
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.08, alpha: 1)
        titleLabel.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 0
        body.font = UIFont.systemFont(ofSize: 15)
        body.textColor = UIColor(white: 0.86, alpha: 1)
        body.numberOfLines = 0
        let next = UIButton(type: .system)
        next.setTitle("Continue", for: .normal)
        next.setTitleColor(.white, for: .normal)
        next.backgroundColor = UIColor(red: 0.231, green: 0.510, blue: 0.965, alpha: 1)
        next.layer.cornerRadius = 12
        next.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        next.addTarget(self, action: #selector(advance), for: .touchUpInside)
        for item in [titleLabel, body, next] {
            item.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(item)
        }
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 80),
            body.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            body.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            next.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            next.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            next.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -40),
            next.heightAnchor.constraint(equalToConstant: 48)
        ])
        render()
    }

    private func render() {
        titleLabel.text = cards[step].0
        body.text = cards[step].1
    }

    @objc private func advance() {
        if step < cards.count - 1 {
            step += 1
            render()
        } else {
            UserDefaults.standard.set(true, forKey: "XADisplay.didOnboard")
            dismiss(animated: true) { self.onFinish?() }
        }
    }
}

final class ConnectionOverlay: UIView {
    var onConnect: ((String) -> Void)?
    var onSettings: (() -> Void)?
    private let field = UITextField()
    private let list = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.07, alpha: 0.96)
        let title = UILabel()
        title.text = "XA Display"
        title.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        title.textColor = .white
        let hint = UILabel()
        hint.text = "Open XA Display on your Mac"
        hint.font = UIFont.systemFont(ofSize: 15)
        hint.textColor = UIColor(white: 0.75, alpha: 1)
        field.placeholder = "Pairing code"
        field.textColor = .white
        field.backgroundColor = UIColor(white: 0.16, alpha: 1)
        field.layer.cornerRadius = 8
        field.autocapitalizationType = .allCharacters
        field.autocorrectionType = .no
        field.font = UIFont.monospacedDigitSystemFont(ofSize: 18, weight: .medium)
        list.font = UIFont.systemFont(ofSize: 14)
        list.textColor = .white
        list.numberOfLines = 0
        let connect = UIButton(type: .system)
        connect.setTitle("Connect", for: .normal)
        connect.setTitleColor(.white, for: .normal)
        connect.backgroundColor = UIColor(red: 0.231, green: 0.510, blue: 0.965, alpha: 1)
        connect.layer.cornerRadius = 12
        connect.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        connect.addTarget(self, action: #selector(connectTapped), for: .touchUpInside)
        let gear = UIButton(type: .system)
        gear.setTitle("Settings", for: .normal)
        gear.setTitleColor(.white, for: .normal)
        if let icon = UIImage(named: "gear") {
            gear.setImage(icon.withRenderingMode(.alwaysTemplate), for: .normal)
            gear.tintColor = .white
            gear.setTitle(" Settings", for: .normal)
        }
        gear.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        let column = UIStackView(arrangedSubviews: [title, hint, list, field, connect, gear])
        column.axis = .vertical
        column.spacing = 12
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        field.heightAnchor.constraint(equalToConstant: 44).isActive = true
        connect.heightAnchor.constraint(equalToConstant: 48).isActive = true
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            column.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func show(macs: [String], code: String) {
        field.text = code
        list.text = macs.isEmpty ? "No saved Macs yet." : macs.joined(separator: "\n")
    }

    @objc private func connectTapped() { onConnect?(field.text ?? "") }
    @objc private func settingsTapped() { onSettings?() }
}
