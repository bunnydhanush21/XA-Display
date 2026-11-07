import UIKit
import XADisplayProtocol

final class DragLoupe: UIView {
    private let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
        isUserInteractionEnabled = false
        isHidden = true
        clipsToBounds = true
        layer.cornerRadius = 60
        layer.borderWidth = 2
        layer.borderColor = UIColor.white.cgColor
        backgroundColor = .black
        imageView.contentMode = .scaleToFill
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { nil }

    func show(image: UIImage, around point: CGPoint, finger: CGPoint) {
        let zoom: CGFloat = 2
        imageView.image = image
        imageView.frame = CGRect(x: bounds.midX - point.x * zoom, y: bounds.midY - point.y * zoom, width: image.size.width * zoom, height: image.size.height * zoom)
        center = CGPoint(x: finger.x, y: max(70, finger.y - 84))
        isHidden = false
    }

    func hide() { isHidden = true }
}

final class TouchChromeController {
    var onLight: ((WindowAction) -> Void)?
    var onDrawer: ((EdgeSystemAction) -> Void)?
    var onMenu: ((Int) -> Void)?
    var onZoom: ((Bool) -> Void)?
    var onMenusRequested: (() -> Void)?

    let loupe = DragLoupe()
    private let drawer = UIView()
    private let drawerStack = UIStackView()
    private let menuPanel = UIScrollView()
    private let menuStack = UIStackView()
    private var lights: [UIButton] = []
    private var handles: [UIView] = []
    private var drawerWidth: NSLayoutConstraint?
    private var drawerOpen = false
    private let lightActions: [WindowAction] = [.pressClose, .pressMinimize, .pressZoom]
    private let drawerActions: [EdgeSystemAction] = EdgeSystemAction.allCases

    func install(in view: UIView) {
        loupe.translatesAutoresizingMaskIntoConstraints = true
        view.addSubview(loupe)
        for _ in 0..<4 {
            let handle = UIView()
            handle.isUserInteractionEnabled = false
            handle.backgroundColor = UIColor(white: 1, alpha: 0.85)
            handle.layer.cornerRadius = 6
            handle.isHidden = true
            view.addSubview(handle)
            handles.append(handle)
        }
        for (index, title) in ["●", "–", "+"].enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 22, weight: .bold)
            button.backgroundColor = index == 0 ? UIColor(red: 0.9, green: 0.25, blue: 0.2, alpha: 0.92) : UIColor(white: 0.15, alpha: 0.92)
            button.layer.cornerRadius = 8
            button.tag = index
            button.isHidden = true
            button.addTarget(self, action: #selector(lightTapped(_:)), for: .touchUpInside)
            view.addSubview(button)
            lights.append(button)
        }
        drawer.backgroundColor = UIColor(white: 0.08, alpha: 0.94)
        drawer.isHidden = true
        drawer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(drawer)
        drawerStack.axis = .vertical
        drawerStack.spacing = 8
        drawerStack.translatesAutoresizingMaskIntoConstraints = false
        drawer.addSubview(drawerStack)
        drawerWidth = drawer.widthAnchor.constraint(equalToConstant: 220)
        NSLayoutConstraint.activate([
            drawer.topAnchor.constraint(equalTo: view.topAnchor),
            drawer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            drawer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            drawerWidth!,
            drawerStack.leadingAnchor.constraint(equalTo: drawer.leadingAnchor, constant: 10),
            drawerStack.trailingAnchor.constraint(equalTo: drawer.trailingAnchor, constant: -10),
            drawerStack.topAnchor.constraint(equalTo: drawer.topAnchor, constant: 16)
        ])
        let titles = ["Notifications", "Mission Control", "App Exposé", "Apps", "Control Center", "Menus", "Zoom in", "Zoom out"]
        for (index, title) in titles.enumerated() {
            let button = makeButton(title)
            button.tag = index
            button.addTarget(self, action: #selector(drawerTapped(_:)), for: .touchUpInside)
            drawerStack.addArrangedSubview(button)
        }
        menuPanel.backgroundColor = UIColor(white: 0.05, alpha: 0.94)
        menuPanel.isHidden = true
        menuPanel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(menuPanel)
        menuStack.axis = .vertical
        menuStack.spacing = 8
        menuStack.translatesAutoresizingMaskIntoConstraints = false
        menuPanel.addSubview(menuStack)
        NSLayoutConstraint.activate([
            menuPanel.topAnchor.constraint(equalTo: view.topAnchor),
            menuPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            menuPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            menuPanel.widthAnchor.constraint(equalToConstant: 280),
            menuStack.leadingAnchor.constraint(equalTo: menuPanel.leadingAnchor, constant: 10),
            menuStack.trailingAnchor.constraint(equalTo: menuPanel.trailingAnchor, constant: -10),
            menuStack.topAnchor.constraint(equalTo: menuPanel.topAnchor, constant: 16),
            menuStack.bottomAnchor.constraint(equalTo: menuPanel.bottomAnchor, constant: -16),
            menuStack.widthAnchor.constraint(equalTo: menuPanel.widthAnchor, constant: -20)
        ])
    }

    func setLarge(_ large: Bool) {
        let side = TouchMetrics.target(requested: large ? 52 : 44, large: large)
        drawerWidth?.constant = large ? 260 : 220
        for button in drawerStack.arrangedSubviews {
            button.constraints.filter { $0.firstAttribute == .height }.forEach { $0.constant = side }
        }
    }

    var menuVisible: Bool { !menuPanel.isHidden }

    func setDrawer(open: Bool) {
        drawerOpen = open
        drawer.isHidden = !open
        if !open { menuPanel.isHidden = true }
    }

    func toggleDrawer() {
        setDrawer(open: !drawerOpen)
    }

    func layout(windows: [CGRect], assist: TouchAssist) {
        let showLights = assist.trafficLights && assist.windowChrome
        let showHandles = assist.windowChrome
        guard let window = windows.first, window.width > 40, window.height > 40 else {
            lights.forEach { $0.isHidden = true }
            handles.forEach { $0.isHidden = true }
            return
        }
        let title = CGRect(x: window.minX, y: window.minY, width: window.width, height: min(CGFloat(WindowChrome.titleBarPoints), window.height))
        let targets = TrafficLights.targets(titleBar: XARect(x: Double(title.minX), y: Double(title.minY), width: Double(title.width), height: Double(title.height)))
        for (button, target) in zip(lights, targets) {
            button.isHidden = !showLights
            button.frame = CGRect(x: target.rect.minX, y: target.rect.minY, width: target.rect.width, height: target.rect.height)
            button.accessibilityLabel = target.id
        }
        let handle = CGFloat(WindowChrome.minimumHit)
        let corners = [
            CGPoint(x: window.minX, y: window.minY),
            CGPoint(x: window.maxX, y: window.minY),
            CGPoint(x: window.minX, y: window.maxY),
            CGPoint(x: window.maxX, y: window.maxY)
        ]
        for (view, corner) in zip(handles, corners) {
            view.isHidden = !showHandles
            view.frame = CGRect(x: corner.x - handle / 2, y: corner.y - handle / 2, width: handle, height: handle)
        }
    }

    func showMenus(_ titles: [String], large: Bool) {
        menuStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let side = TouchMetrics.target(requested: large ? 52 : 44, large: large)
        if titles.isEmpty {
            let label = UILabel()
            label.textColor = .white
            label.numberOfLines = 0
            label.text = "No menus yet. The Mac reads them with Accessibility."
            menuStack.addArrangedSubview(label)
        }
        for (index, title) in titles.enumerated() {
            let button = makeButton(title)
            button.tag = index
            button.constraints.filter { $0.firstAttribute == .height }.forEach { $0.constant = side }
            button.addTarget(self, action: #selector(menuTapped(_:)), for: .touchUpInside)
            menuStack.addArrangedSubview(button)
        }
        menuPanel.isHidden = false
        drawer.isHidden = true
    }

    private func makeButton(_ title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        button.titleLabel?.numberOfLines = 2
        button.backgroundColor = UIColor(white: 0.2, alpha: 1)
        button.layer.cornerRadius = 8
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        button.accessibilityLabel = title
        return button
    }

    @objc private func lightTapped(_ sender: UIButton) {
        guard sender.tag >= 0, sender.tag < lightActions.count else { return }
        onLight?(lightActions[sender.tag])
    }

    @objc private func drawerTapped(_ sender: UIButton) {
        if sender.tag >= 0 && sender.tag < drawerActions.count {
            onDrawer?(drawerActions[sender.tag])
        } else if sender.tag == drawerActions.count {
            onMenusRequested?()
        } else if sender.tag == drawerActions.count + 1 {
            onZoom?(true)
        } else {
            onZoom?(false)
        }
    }

    @objc private func menuTapped(_ sender: UIButton) {
        onMenu?(sender.tag)
        menuPanel.isHidden = true
    }
}
