import AVFoundation
import UIKit
import XADisplayProtocol

extension ReceiverViewController {
    func perform(_ gesture: FingerGesture, finger: CGPoint, pointer: CGPoint, time: Double) {
        if features.trackpadMode {
            chrome.loupe.hide()
            performTrackpad(gesture)
            return
        }
        if case .tap(let point) = gesture {
            handleTap(point, time: time)
            return
        }
        if case .drag = gesture {
            titleTimer?.invalidate()
            titleArbiter.cancel()
        }
        if case .drag(let phase, _) = gesture, let resize = resizing, assist.windowChrome {
            sendResize(phase, pointer: pointer, resize: resize)
            return
        }
        if case .drag(.ended, _) = gesture, assist.windowChrome {
            flickTitleBar(at: finger, time: time)
        }
        if case .drag = gesture, assist.loupeWhileDragging {
            showLoupe(at: finger)
        }
        forwardLegacy(gesture)
        for intent in GestureMapper.intents(for: gesture) {
            input.send(intent: intent)
        }
    }
    func handleTap(_ point: XAPoint, time: Double) {
        let tuning = features.gestureTuning.clamped()
        let gap = time - (lastRepeatTime ?? -10)
        if gap > tuning.doubleTapWindow && !RepeatGate.allow(now: time, last: lastRepeatTime, interval: assist.ignoreRepeat) {
            return
        }
        lastRepeatTime = time
        guard assist.windowChrome else {
            sendClick(point)
            return
        }
        let frames = windowFrames
        switch titleArbiter.tap(point: point, time: time, windows: frames, titleHeight: titleHeightNormalized()) {
        case .click(let clickPoint):
            sendClick(clickPoint)
        case .pending:
            titleTimer?.invalidate()
            let wait = features.gestureTuning.clamped().doubleTapWindow
            titleTimer = Timer.scheduledTimer(withTimeInterval: wait, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                if case .click(let clickPoint) = self.titleArbiter.flush(now: time + wait + 0.05) { self.sendClick(clickPoint) }
            }
        case .fillToggle:
            titleTimer?.invalidate()
            input.sendWindow(.fillToggle)
        }
    }
    func sendClick(_ point: XAPoint) {
        forwardLegacy(.tap(point))
        for intent in GestureMapper.intents(for: .tap(point)) { input.send(intent: intent) }
    }
    func sendResize(_ phase: FingerGesture.DragPhase, pointer: CGPoint, resize: (index: Int, corner: ResizeCorner)) {
        guard phase == .moved || phase == .ended else { return }
        let content = contentSize()
        guard content.width > 1, content.height > 1, let origin = resizeOrigin else { return }
        let current = XAPoint(x: Double(pointer.x), y: Double(pointer.y))
        let dx = (current.x - origin.x) / content.width
        let dy = (current.y - origin.y) / content.height
        resizeOrigin = current
        input.sendChrome(op: .resize, index: UInt16(resize.corner.rawValue), windowIndex: UInt16(resize.index), dx: dx, dy: dy)
        if phase == .ended { resizing = nil }
    }
    func flickTitleBar(at finger: CGPoint, time: Double) {
        guard let start = dragOriginView else { return }
        let dt = max(0.016, time - dragOriginTime)
        let dx = Double(finger.x) - start.x
        let dy = Double(finger.y) - start.y
        let speed = xaHypot(dx, dy) / dt
        let frames = windowViewFrames()
        guard let region = TitleBarFlick.region(start: start, dx: dx, dy: dy, speed: speed, windows: frames) else { return }
        switch region {
        case .leftHalf: input.sendWindow(.snapLeft)
        case .rightHalf: input.sendWindow(.snapRight)
        case .topLeft: input.sendWindow(.tileTopLeft)
        case .topRight: input.sendWindow(.tileTopRight)
        case .bottomLeft: input.sendWindow(.tileBottomLeft)
        case .bottomRight: input.sendWindow(.tileBottomRight)
        }
    }
    func performTrackpad(_ gesture: FingerGesture) {
        switch gesture {
        case .drag(.moved, _), .relativeMove:
            break
        default:
            break
        }
        if case .drag(.moved, let point) = gesture {
            let delta = TrackpadAcceleration.apply(dx: point.x, dy: point.y, precision: features.precisionMode)
            let content = contentSize()
            guard content.width > 0, content.height > 0 else { return }
            let moved = trackpad.apply(normalizedDelta: XAPoint(x: delta.x / content.width, y: delta.y / content.height))
            input.send(intent: .mouse(phase: .move, button: .left, x: moved.x, y: moved.y, space: .absoluteNormalized))
            cursorNorm = CGPoint(x: moved.x, y: moved.y)
            cursorVisible = true
            layoutCursor()
        } else if case .tap = gesture {
            input.send(intent: .mouse(phase: .down, button: .left, x: trackpad.normalized.x, y: trackpad.normalized.y, space: .absoluteNormalized))
            input.send(intent: .mouse(phase: .up, button: .left, x: trackpad.normalized.x, y: trackpad.normalized.y, space: .absoluteNormalized))
        } else if case .longPress = gesture {
            input.send(intent: .mouse(phase: .down, button: .right, x: trackpad.normalized.x, y: trackpad.normalized.y, space: .absoluteNormalized))
            input.send(intent: .mouse(phase: .up, button: .right, x: trackpad.normalized.x, y: trackpad.normalized.y, space: .absoluteNormalized))
        } else {
            for intent in GestureMapper.intents(for: gesture) { input.send(intent: intent) }
        }
    }
    func forwardLegacy(_ gesture: FingerGesture) {
        switch gesture {
        case .tap(let point), .longPress(let point):
            receiver.sendTouch(phase: "began", x: point.x, y: point.y)
            receiver.sendTouch(phase: "ended", x: point.x, y: point.y)
        case .drag(let phase, let point):
            let name: String
            switch phase {
            case .began: name = "began"
            case .moved: name = "moved"
            case .ended: name = "ended"
            }
            receiver.sendTouch(phase: name, x: point.x, y: point.y)
        case .scroll(let dx, let dy, _):
            receiver.sendScroll(dx: dx, dy: dy)
        default:
            break
        }
    }
    func normalize(_ location: XAPoint) -> XAPoint? {
        let rotation: XARotation
        switch features.inputRotation {
        case 90: rotation = .clockwise90
        case 180: rotation = .clockwise180
        case 270: rotation = .clockwise270
        default: rotation = .identity
        }
        let video = videoSize == .zero ? XASize(width: 1440, height: 1080) : XASize(width: Double(videoSize.width), height: Double(videoSize.height))
        return PadInputService().normalized(
            point: location,
            view: XASize(width: Double(videoView.bounds.width), height: Double(videoView.bounds.height)),
            video: video,
            rotation: rotation,
            pixelsPerPoint: Double(UIScreen.main.scale)
        )
    }
    func contentSize() -> XASize {
        let rect = CoordinateMapper.contentRect(
            view: XASize(width: Double(videoView.bounds.width), height: Double(videoView.bounds.height)),
            video: XASize(width: Double(max(videoSize.width, 1)), height: Double(max(videoSize.height, 1)))
        )
        return rect.size
    }
    func addGestures() {
        let scroll = UIPanGestureRecognizer(target: self, action: #selector(scrollPan(_:)))
        scroll.minimumNumberOfTouches = 2
        scroll.maximumNumberOfTouches = 2
        view.addGestureRecognizer(scroll)
        scrollRecognizer = scroll
        let three = UIPanGestureRecognizer(target: self, action: #selector(threePan(_:)))
        three.minimumNumberOfTouches = 3
        three.maximumNumberOfTouches = 3
        view.addGestureRecognizer(three)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        view.addGestureRecognizer(pinch)
        let pillTap = UITapGestureRecognizer(target: self, action: #selector(showPill))
        pillTap.numberOfTouchesRequired = 3
        view.addGestureRecognizer(pillTap)
        let twoTap = UITapGestureRecognizer(target: self, action: #selector(twoTap))
        twoTap.numberOfTouchesRequired = 2
        view.addGestureRecognizer(twoTap)
        let twoHold = UILongPressGestureRecognizer(target: self, action: #selector(twoHold(_:)))
        twoHold.numberOfTouchesRequired = 2
        twoHold.minimumPressDuration = 0.35
        view.addGestureRecognizer(twoHold)
        let sidebar = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(edgePan(_:)))
        sidebar.edges = .left
        view.addGestureRecognizer(sidebar)
        sidebarEdge = sidebar
        let drawer = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(drawerPan(_:)))
        drawer.edges = .right
        view.addGestureRecognizer(drawer)
        drawerEdge = drawer
    }
    @objc func scrollPan(_ gesture: UIPanGestureRecognizer) {
        guard settingsDocument.twoFingerScroll, gesture.state == .changed || gesture.state == .ended else { return }
        let translation = gesture.translation(in: videoView)
        gesture.setTranslation(.zero, in: videoView)
        let gain = features.gestureTuning.clamped().scrollGain
        let pixels = CoordinateMapper.scrollPixels(
            viewDelta: XAPoint(x: Double(translation.x) * gain, y: Double(translation.y) * gain),
            contentSize: contentSize(),
            videoPixelSize: XASize(width: Double(max(videoSize.width, 1)), height: Double(max(videoSize.height, 1)))
        )
        let sendInertia = gesture.state == .ended && features.scrollInertia
        input.send(intent: .scroll(dx: pixels.x, dy: pixels.y, inertia: false))
        receiver.sendScroll(dx: pixels.x, dy: pixels.y)
        if sendInertia {
            let velocity = gesture.velocity(in: videoView)
            let steps = MacTouchScroll.steps(velocityX: Double(velocity.x) * 0.016 * gain, velocityY: Double(velocity.y) * 0.016 * gain)
            for step in steps {
                let extra = CoordinateMapper.scrollPixels(
                    viewDelta: XAPoint(x: step.dx, y: step.dy), contentSize: contentSize(), videoPixelSize: XASize(width: Double(max(videoSize.width, 1)), height: Double(max(videoSize.height, 1))))
                input.send(intent: .scroll(dx: extra.x, dy: extra.y, inertia: true))
                receiver.sendScroll(dx: extra.x, dy: extra.y)
            }
        }
    }
    @objc func threePan(_ gesture: UIPanGestureRecognizer) {
        guard features.threeFingerShortcuts, gesture.state == .ended else { return }
        let translation = gesture.translation(in: view)
        guard let action = ThreeFingerMapper.action(dx: Double(translation.x), dy: Double(translation.y)) else { return }
        for intent in ThreeFingerMapper.intents(for: action) { input.send(intent: intent) }
    }
    @objc func pinched(_ gesture: UIPinchGestureRecognizer) {
        guard features.pinchMagnifier, gesture.state == .changed || gesture.state == .ended else { return }
        let point = gesture.location(in: videoView)
        let around = normalize(XAPoint(x: Double(point.x), y: Double(point.y))) ?? XAPoint(x: 0.5, y: 0.5)
        magnifier.pinch(by: Double(gesture.scale), around: around)
        gesture.scale = 1
        applyMagnifier()
    }
    @objc func twoTap() {
        guard settingsDocument.rightClick != "longPress" else { return }
        let point = cursorNorm
        let gesture = FingerGesture.twoFingerTap(XAPoint(x: Double(point.x), y: Double(point.y)))
        for intent in GestureMapper.intents(for: gesture) { input.send(intent: intent) }
    }
    @objc func twoHold(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: videoView)
        let normalized = normalize(XAPoint(x: Double(point.x), y: Double(point.y))) ?? XAPoint(x: 0.5, y: 0.5)
        for intent in GestureMapper.intents(for: .twoFingerLongPress(normalized)) { input.send(intent: intent) }
    }
    @objc func edgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard features.gestureTuning.sidebarOnLeft, gesture.state == .ended, gesture.translation(in: view).x > 24 else { return }
        collapsed = false
        applyChrome()
    }
    @objc func drawerPan(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard assist.edgeDrawer, gesture.state == .ended else { return }
        let start = gesture.location(in: view)
        if EdgeDrawerGate.shouldOpen(startX: Double(start.x), viewWidth: Double(view.bounds.width), translationX: Double(gesture.translation(in: view).x)) {
            chrome.toggleDrawer()
        }
    }
    func wireChrome() {
        chrome.onLight = { [weak self] action in self?.input.sendWindow(action) }
        chrome.onDrawer = { [weak self] action in self?.fireEdge(action) }
        chrome.onMenu = { [weak self] index in
            self?.input.sendChrome(op: .menu, index: UInt16(index), windowIndex: 0, dx: 0, dy: 0)
        }
        chrome.onMenusRequested = { [weak self] in
            guard let self = self, self.assist.menuOverlay else { return }
            self.chrome.showMenus(self.menuTitles, large: self.assist.largeButtons)
        }
        chrome.onZoom = { [weak self] zoomIn in self?.sendZoom(zoomIn) }
    }
    func fireEdge(_ action: EdgeSystemAction) {
        switch EdgeRouter.route(assist.binding(for: action)) {
        case .key(let shortcut):
            sendShortcut(shortcut)
        case .accessibility:
            input.sendWindow(action.windowAction)
        }
        chrome.setDrawer(open: false)
    }
    func sendZoom(_ zoomIn: Bool) {
        let binding = ZoomProfiles.resolve(bundleID: frontBundle, bindings: assist.zoomBindings)
        let inputName = zoomIn ? binding.zoomIn : binding.zoomOut
        sendShortcut(KeyShortcut(input: inputName, modifiers: XAModifierMask(rawValue: binding.modifiers)))
    }
}
