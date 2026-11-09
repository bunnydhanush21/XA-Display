import AppKit

@main
enum XADisplayMain {
    @MainActor
    static func main() {
        HostLaunch.start(runLoop: true)
    }
}

@MainActor
enum HostLaunch {
    static func start(runLoop: Bool) {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        AppDelegate.retainForLaunch(delegate)
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        if runLoop {
            app.run()
        } else {
            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        }
    }
}
