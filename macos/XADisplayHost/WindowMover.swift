import ApplicationServices
import CoreGraphics
import Foundation
import XADisplayProtocol

struct LiveWindow {
    var snapshot: WindowSnapshot
    var element: AXUIElement
}

enum WindowMover {
    static func windows() -> [LiveWindow] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var result: [LiveWindow] = []
        let byPID = Dictionary(grouping: info) { ($0[kCGWindowOwnerPID as String] as? Int) ?? 0 }
        for (pid, entries) in byPID where pid > 0 {
            let app = AXUIElementCreateApplication(pid_t(pid))
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else { continue }
            for element in windows {
                guard let frame = axFrame(element) else { continue }
                let title = axString(element, kAXTitleAttribute) ?? ""
                let number = entries.first.flatMap { $0[kCGWindowNumber as String] as? Int } ?? result.count
                let snapshot = WindowSnapshot(id: number, ownerPID: pid, title: title, bounds: frame)
                result.append(LiveWindow(snapshot: snapshot, element: element))
            }
        }
        return result
    }

    static func recover(from display: XARect, to main: XARect) -> Int {
        let live = windows()
        let stranded = WindowRecovery.stranded(live.map(\.snapshot), on: display)
        var moved = 0
        for item in live where stranded.contains(where: { $0.id == item.snapshot.id && $0.ownerPID == item.snapshot.ownerPID }) {
            let frame = WindowRecovery.relocate(item.snapshot, from: display, to: main)
            if setFrame(item.element, frame) { moved += 1 }
        }
        return moved
    }

    static func apply(zone: SnapZone, virtual: XARect, main: XARect) -> Bool {
        let targetDisplay = zone == .mainDisplay ? main : virtual
        let live = windows()
        guard let window = live.first(where: { $0.snapshot.bounds.intersects(zone == .mainDisplay ? virtual : virtual) }) ?? live.first else {
            return false
        }
        let frame = WindowSnap.frame(zone: zone, virtualDisplay: virtual, mainDisplay: main)
        _ = targetDisplay
        return setFrame(window.element, frame)
    }

    static func mainDisplayFrame() -> XARect {
        let id = CGMainDisplayID()
        let bounds = CGDisplayBounds(id)
        return XARect(x: Double(bounds.origin.x), y: Double(bounds.origin.y), width: Double(bounds.width), height: Double(bounds.height))
    }

    static func displayFrame(_ id: CGDirectDisplayID) -> XARect {
        let bounds = CGDisplayBounds(id)
        return XARect(x: Double(bounds.origin.x), y: Double(bounds.origin.y), width: Double(bounds.width), height: Double(bounds.height))
    }

    private static func setFrame(_ element: AXUIElement, _ frame: XARect) -> Bool {
        var origin = CGPoint(x: frame.origin.x, y: frame.origin.y)
        var size = CGSize(width: frame.width, height: frame.height)
        guard let position = AXValueCreate(.cgPoint, &origin), let axSize = AXValueCreate(.cgSize, &size) else { return false }
        let moved = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position) == .success
        let sized = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, axSize) == .success
        return moved || sized
    }

    private static func axFrame(_ element: AXUIElement) -> XARect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionRef = positionValue, let sizeRef = sizeValue else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return nil }
        return XARect(x: Double(position.x), y: Double(position.y), width: Double(size.width), height: Double(size.height))
    }

    private static func axString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
