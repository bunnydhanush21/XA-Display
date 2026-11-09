@preconcurrency import AppKit
import XCTest

@testable import XADisplayHost

@MainActor
final class HostLaunchTests: XCTestCase {
    func testStartupAssignsTheDelegateAndStatusButton() {
        HostLaunch.start(runLoop: false)
        XCTAssertTrue(NSApp.delegate is AppDelegate)
        let delegate = NSApp.delegate as? AppDelegate
        XCTAssertNotNil(delegate?.statusButtonForTest)
    }
}
