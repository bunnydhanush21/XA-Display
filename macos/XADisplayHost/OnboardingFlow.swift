@preconcurrency import AppKit
@preconcurrency import ApplicationServices

@MainActor
final class OnboardingFlow: NSObject {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    private let titleLabel = NSTextField(labelWithString: "")
    private let body = NSTextField(wrappingLabelWithString: "")
    private let primary = NSButton(title: "Continue", target: nil, action: nil)
    private let secondary = NSButton(title: "Open Settings", target: nil, action: nil)
    private var step = 0
    private var timer: Timer?
    var pairingCode = ""
    var onFinish: (() -> Void)?

    override init() {
        super.init()
        window.title = "Welcome to XA Display"
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.frame = NSRect(x: 28, y: 280, width: 460, height: 32)
        body.frame = NSRect(x: 28, y: 110, width: 460, height: 160)
        primary.frame = NSRect(x: 360, y: 28, width: 130, height: 32)
        primary.bezelStyle = .rounded
        primary.target = self
        primary.action = #selector(advance)
        secondary.frame = NSRect(x: 28, y: 28, width: 180, height: 32)
        secondary.bezelStyle = .rounded
        secondary.target = self
        secondary.action = #selector(openSettings)
        window.contentView?.addSubview(titleLabel)
        window.contentView?.addSubview(body)
        window.contentView?.addSubview(primary)
        window.contentView?.addSubview(secondary)
        render()
    }

    func show() {
        XALog.write(XALog.ui, "onboarding")
        step = 0
        render()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollPermissions() }
        }
    }

    private func render() {
        secondary.isHidden = step == 0 || step == 3
        switch step {
        case 0:
            titleLabel.stringValue = "A second display on your iPad"
            body.stringValue =
                "XA Display extends the Mac onto an iPad. The pointer is a normal Mac cursor made of CGEvent clicks. It is not a native touchscreen. USB is tried first. Wi-Fi is the fallback."
            primary.title = "Continue"
        case 1:
            titleLabel.stringValue = "Allow Screen Recording"
            body.stringValue =
                granted(CGPreflightScreenCaptureAccess())
                ? "Screen Recording is on. The next screen is Accessibility."
                : "XA Display captures only the virtual display it creates. Open System Settings, allow Screen Recording, then quit and reopen the host if capture stays denied."
            primary.title = granted(CGPreflightScreenCaptureAccess()) ? "Continue" : "Waiting"
            secondary.title = "Open Screen Recording"
        case 2:
            titleLabel.stringValue = "Allow Accessibility"
            body.stringValue =
                AXIsProcessTrusted()
                ? "Accessibility is on. The pointer, keyboard, and window recovery can run."
                : "Accessibility lets the host move the pointer and recover windows. Those are public CGEvent and AX actions."
            primary.title = AXIsProcessTrusted() ? "Continue" : "Waiting"
            secondary.title = "Open Accessibility"
        default:
            titleLabel.stringValue = "Pair the iPad"
            body.stringValue = "Enter this pairing code in XA Display on the iPad:\n\n\(pairingCode)\n\nPlug in the cable, or join the same Wi-Fi. The iPad app listens. This Mac connects to it."
            primary.title = "Done"
            secondary.isHidden = true
        }
    }

    private func granted(_ value: Bool) -> Bool { value }

    private func pollPermissions() {
        if step == 1, CGPreflightScreenCaptureAccess() { step = 2 } else if step == 2, AXIsProcessTrusted() { step = 3 } else { return }
        render()
    }

    @objc func advance() {
        if step < 3 {
            step += 1
            render()
        } else {
            timer?.invalidate()
            window.close()
            onFinish?()
        }
    }

    @objc private func openSettings() {
        if step == 1 { CGRequestScreenCaptureAccess() }
        if step == 2 {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
    }
}
