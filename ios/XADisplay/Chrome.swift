import AVFoundation
import UIKit
import XADisplayProtocol

final class VideoContainerView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
}

final class SidebarView: UIView {
    var onToggle: ((XAModifierMask) -> Void)?
    var onEsc: (() -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onKeyboard: (() -> Void)?
    var onDisconnect: (() -> Void)?
    var onSettings: (() -> Void)?
    var onPrecision: (() -> Void)?
    var onTrackpad: (() -> Void)?
    var onMacs: (() -> Void)?
    var onMedia: (() -> Void)?
    private var mediaButton: UIButton?
    var onCollapse: (() -> Void)?
    private var modifierButtons: [XAModifierMask: UIButton] = [:]
    private var heights: [NSLayoutConstraint] = []
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.08, alpha: 0.72)
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur)
        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12)
        ])
        add(title: "Menu") { [weak self] in self?.onCollapse?() }
        addModifier("Cmd", .command)
        addModifier("Opt", .option)
        addModifier("Ctrl", .control)
        addModifier("Shift", .shift)
        add(title: "Esc") { [weak self] in self?.onEsc?() }
        add(title: "Undo") { [weak self] in self?.onUndo?() }
        add(title: "Redo") { [weak self] in self?.onRedo?() }
        add(title: "Keys") { [weak self] in self?.onKeyboard?() }
        add(title: "Trackpad") { [weak self] in self?.onTrackpad?() }
        add(title: "Precise") { [weak self] in self?.onPrecision?() }
        add(title: "Macs") { [weak self] in self?.onMacs?() }
        let media = makeButton("Media")
        mediaButton = media
        media.isHidden = true
        let mediaTarget = ActionBox { [weak self] in self?.onMedia?() }
        objc_setAssociatedObject(media, &ActionBox.key, mediaTarget, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        media.addTarget(mediaTarget, action: #selector(ActionBox.fire), for: .touchUpInside)
        stack.addArrangedSubview(media)
        add(title: "Settings") { [weak self] in self?.onSettings?() }
        add(title: "Disconnect") { [weak self] in self?.onDisconnect?() }
    }

    required init?(coder: NSCoder) { nil }

    func setModifier(_ mask: XAModifierMask, on: Bool) {
        modifierButtons[mask]?.backgroundColor = on ? UIColor(red: 0.91, green: 0.66, blue: 0.22, alpha: 1) : UIColor(white: 0.2, alpha: 1)
    }

    func setCollapsed(_ collapsed: Bool) {
        stack.isHidden = collapsed
    }

    func setShowsMedia(_ on: Bool) {
        mediaButton?.isHidden = !on
    }

    func setLarge(_ large: Bool) {
        let height = TouchMetrics.target(requested: large ? 52 : 44, large: large)
        for constraint in heights { constraint.constant = height }
    }

    private func addModifier(_ title: String, _ mask: XAModifierMask) {
        let button = makeButton(title)
        button.addTarget(self, action: #selector(modifierTapped(_:)), for: .touchUpInside)
        button.tag = Int(mask.rawValue)
        modifierButtons[mask] = button
        stack.addArrangedSubview(button)
    }

    private func add(title: String, action: @escaping () -> Void) {
        let button = makeButton(title)
        let target = ActionBox(action)
        objc_setAssociatedObject(button, &ActionBox.key, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        button.addTarget(target, action: #selector(ActionBox.fire), for: .touchUpInside)
        stack.addArrangedSubview(button)
    }

    private static func iconName(_ title: String) -> String {
        switch title {
        case "Undo": return "undo"
        case "Redo": return "redo"
        case "Keys": return "keyboard"
        case "Settings": return "gear"
        case "Macs": return "display"
        default: return ""
        }
    }

    private func makeButton(_ title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        if let icon = UIImage(named: Self.iconName(title)) {
            button.setImage(icon.withRenderingMode(.alwaysTemplate), for: .normal)
            button.tintColor = .white
        }
        button.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        button.backgroundColor = UIColor(white: 0.2, alpha: 1)
        button.layer.cornerRadius = 8
        let height = button.heightAnchor.constraint(equalToConstant: 44)
        height.isActive = true
        heights.append(height)
        button.accessibilityLabel = title
        return button
    }

    @objc private func modifierTapped(_ sender: UIButton) {
        onToggle?(XAModifierMask(rawValue: UInt8(sender.tag)))
    }
}

private final class ActionBox: NSObject {
    static var key: UInt8 = 0
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire() { action() }
}

final class CommandStripView: UIView {
    var onItem: ((CommandStripItem) -> Void)?
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.05, alpha: 0.9)
        stack.axis = .horizontal
        stack.spacing = 6
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
        for item in CommandStripItem.standard {
            let button = UIButton(type: .system)
            button.setTitle(item.title, for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .medium)
            button.backgroundColor = UIColor(white: 0.18, alpha: 1)
            button.layer.cornerRadius = 6
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
            button.accessibilityLabel = item.title
            button.tag = CommandStripItem.standard.firstIndex(where: { $0.id == item.id }) ?? 0
            button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
    }

    required init?(coder: NSCoder) { nil }

    @objc private func tapped(_ sender: UIButton) {
        let items = CommandStripItem.standard
        guard sender.tag >= 0, sender.tag < items.count else { return }
        onItem?(items[sender.tag])
    }
}

final class StatsOverlay: UILabel {
    override init(frame: CGRect) {
        super.init(frame: frame)
        font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        textColor = .white
        backgroundColor = UIColor(white: 0, alpha: 0.55)
        numberOfLines = 0
        textAlignment = .center
        layer.cornerRadius = 8
        clipsToBounds = true
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { nil }
}

final class KeyInputView: UIView, UIKeyInput {
    var onText: ((String) -> Void)?
    var onDelete: (() -> Void)?
    var hasText: Bool { true }
    func insertText(_ text: String) { onText?(text) }
    func deleteBackward() { onDelete?() }
    override var canBecomeFirstResponder: Bool { true }
}
