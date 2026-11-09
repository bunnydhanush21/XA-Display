import XCTest

final class LaunchScreenshotTests: XCTestCase {
    func testLaunchShowsTheConnectionScreen() {
        let app = XCUIApplication()
        app.launch()
        let shot = XCUIScreen.main.screenshot()
        if let dir = ProcessInfo.processInfo.environment["XA_SCREENSHOT_DIR"], !dir.isEmpty {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("ipad-launch.png")
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: url)
        }
        XCTAssertTrue(app.exists)
    }
}
