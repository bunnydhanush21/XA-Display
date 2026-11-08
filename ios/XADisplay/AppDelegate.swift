import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        XALog.write(XALog.ui, "ipad launch")
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = ReceiverViewController()
        window.backgroundColor = .black
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
