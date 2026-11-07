import AppKit
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

    static func catalog(on display: XARect) -> (windows: [XARect], menus: [String], bundleID: String) {
        let ordered = orderedWindows(on: display)
        publishedWindows = ordered
        let rects = ordered.map { ChromeWire.normalized($0.snapshot.bounds, in: display) }
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let pid = frontPID ?? pid_t(ordered.first?.snapshot.ownerPID ?? 0)
        let menus = menuEntries(pid: pid)
        let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        return (rects, menus, bundle)
    }

    static func fillToggle(on display: XARect) -> Bool {
        guard let window = front(on: display) else { return false }
        let key = "\(window.snapshot.ownerPID):\(window.snapshot.id)"
        let result = FillToggle.toggle(window: window.snapshot.bounds, display: display, saved: savedFrames[key])
        if let saved = result.saved {
            savedFrames[key] = saved
        } else {
            savedFrames.removeValue(forKey: key)
        }
        return setFrame(window.element, result.frame)
    }

    static func tile(_ region: TileRegion, on display: XARect) -> Bool {
        guard let window = front(on: display) else { return false }
        return setFrame(window.element, QuarterFrame.frame(region, display: display))
    }

    static func resize(windowIndex: Int, corner: ResizeCorner, translation: XAPoint, on display: XARect) -> Bool {
        let windows = publishedWindows.isEmpty ? orderedWindows(on: display) : publishedWindows
        guard windowIndex >= 0, windowIndex < windows.count else { return false }
        let window = windows[windowIndex]
        guard let frame = axFrame(window.element) else { return false }
        return setFrame(window.element, WindowResize.resized(window: frame, corner: corner, translation: translation))
    }

    static func pressTraffic(_ action: WindowAction, on display: XARect) -> Bool {
        let attribute: String
        switch action {
        case .pressClose: attribute = kAXCloseButtonAttribute
        case .pressMinimize: attribute = kAXMinimizeButtonAttribute
        case .pressZoom: attribute = kAXZoomButtonAttribute
        default: return false
        }
        guard let window = front(on: display) else { return false }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window.element, attribute as CFString, &value) == .success,
              let value = value else { return false }
        return AXUIElementPerformAction(value as! AXUIElement, kAXPressAction as CFString) == .success
    }

    static func pressMenu(index: Int) -> Bool {
        guard index >= 0, index < publishedMenus.count else { return false }
        return AXUIElementPerformAction(publishedMenus[index], kAXPressAction as CFString) == .success
    }

    static func pressExtra(matching needle: String) -> Bool {
        let needle = needle.lowercased()
        for app in NSWorkspace.shared.runningApplications {
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(ax, "AXExtrasMenuBar" as CFString, &value) == .success else { continue }
            let extras = axElements(value)
            for extra in extras {
                let title = (axString(extra, kAXTitleAttribute) ?? axString(extra, kAXDescriptionAttribute) ?? "").lowercased()
                if title.contains(needle), AXUIElementPerformAction(extra, kAXPressAction as CFString) == .success {
                    return true
                }
                for child in axChildren(extra) {
                    let childTitle = (axString(child, kAXTitleAttribute) ?? axString(child, kAXDescriptionAttribute) ?? "").lowercased()
                    if childTitle.contains(needle), AXUIElementPerformAction(child, kAXPressAction as CFString) == .success {
                        return true
                    }
                }
            }
        }
        return false
    }

    private static var publishedWindows: [LiveWindow] = []
    private static var publishedMenus: [AXUIElement] = []
    private static var savedFrames: [String: XARect] = [:]

    private static func front(on display: XARect) -> LiveWindow? {
        if let published = publishedWindows.first { return published }
        return orderedWindows(on: display).first
    }

    private static func orderedWindows(on display: XARect) -> [LiveWindow] {
        guard display.width > 1, display.height > 1 else { return [] }
        let live = windows()
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return live.filter { $0.snapshot.bounds.intersects(display) }
        }
        var result: [LiveWindow] = []
        for entry in info {
            let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.intValue ?? (entry[kCGWindowOwnerPID as String] as? Int) ?? 0
            guard pid > 0,
                  let frame = cgFrame(entry), frame.intersects(display) else { continue }
            guard let match = live.first(where: { item in
                item.snapshot.ownerPID == pid && framesClose(item.snapshot.bounds, frame)
                    && !result.contains(where: { $0.snapshot.id == item.snapshot.id && $0.snapshot.ownerPID == item.snapshot.ownerPID })
            }) else { continue }
            result.append(match)
            if result.count == 16 { break }
        }
        if !result.isEmpty { return result }
        return Array(live.filter { $0.snapshot.bounds.intersects(display) }.prefix(16))
    }

    private static func framesClose(_ a: XARect, _ b: XARect) -> Bool {
        abs(a.minX - b.minX) < 12 && abs(a.minY - b.minY) < 12 && abs(a.width - b.width) < 24 && abs(a.height - b.height) < 24
    }

    private static func cgFrame(_ entry: [String: Any]) -> XARect? {
        guard let bounds = entry[kCGWindowBounds as String] as? NSDictionary else { return nil }
        func number(_ key: String) -> Double? { (bounds[key] as? NSNumber)?.doubleValue }
        guard let x = number("X"), let y = number("Y"), let width = number("Width"), let height = number("Height") else { return nil }
        return XARect(x: x, y: y, width: width, height: height)
    }

    private static func menuEntries(pid: pid_t) -> [String] {
        publishedMenus = []
        guard pid > 0 else { return [] }
        let app = AXUIElementCreateApplication(pid)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &bar) == .success else { return [] }
        var titles: [String] = []
        var elements: [AXUIElement] = []
        for menu in axElements(bar) {
            let menuTitle = axString(menu, kAXTitleAttribute) ?? ""
            let items = axChildren(menu)
            if items.isEmpty {
                if !menuTitle.isEmpty {
                    titles.append(menuTitle)
                    elements.append(menu)
                }
                continue
            }
            for item in items {
                let role = axString(item, kAXRoleAttribute) ?? ""
                if role == "AXSeparator" { continue }
                guard let title = axString(item, kAXTitleAttribute), !title.isEmpty else { continue }
                titles.append(menuTitle.isEmpty ? title : "\(menuTitle) · \(title)")
                elements.append(item)
                if titles.count == 40 { break }
            }
            if titles.count == 40 { break }
        }
        publishedMenus = elements
        return titles
    }

    private static func axElements(_ value: CFTypeRef?) -> [AXUIElement] {
        if let list = value as? [AXUIElement] { return list }
        guard let value = value else { return [] }
        return axChildren(value as! AXUIElement)
    }

    private static func axChildren(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
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
