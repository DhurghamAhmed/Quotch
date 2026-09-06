import AppKit
import SwiftUI
import Combine

enum Reveal {
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static var open: Animation? {
        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.9)
    }

    static var close: Animation? {
        reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 1)
    }

    static var chrome: Animation? {
        reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.86)
    }

    static var value: Animation? {
        reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85)
    }

    static func row(index: Int) -> Animation? {
        reduceMotion
            ? nil
            : .spring(response: 0.48, dampingFraction: 0.92).delay(0.045 * Double(index) + 0.05)
    }

    static var settle: TimeInterval { reduceMotion ? 0 : 0.3 }
}

@MainActor
final class NotchController: NSObject, ObservableObject {

    @Published private(set) var isExpanded = false
    @Published private(set) var isDragging = false
    @Published private(set) var placement: Placement
    @Published private(set) var frames: PanelFrames

    private let store: UsageStore
    private var panel: NotchPanel?
    private var hostView: HoverHostView?
    private var dragHandle: DragHandleView?
    private var collapseWorkItem: DispatchWorkItem?

    private var shrinkWorkItem: DispatchWorkItem?
    private var dragStartMouse: CGPoint?
    private var dragStartOrigin: CGPoint?
    private var suppressExpandUntil = Date.distantPast
    private var cancellables = Set<AnyCancellable>()

    init(store: UsageStore) {
        self.store = store
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let stored = PlacementStore.load()
        self.placement = stored
        self.frames = PlacementSolver.frames(
            for: stored,
            on: screen,
            railItems: max(1, store.activeProviders.count)
        )
        super.init()

        store.$settings
            .sink { [weak self] _ in
                Task { @MainActor in self?.relayout() }
            }
            .store(in: &cancellables)
    }

    func start() {
        buildPanel()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        panel?.orderOut(nil)
        panel = nil
    }

    private var currentScreen: NSScreen {
        panel?.screen ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func buildPanel() {
        recomputeFrames()

        let panel = NotchPanel(contentRect: frames.collapsed)

        let host = HoverHostView(frame: NSRect(origin: .zero, size: frames.collapsed.size))
        host.autoresizingMask = [.width, .height]
        host.onHoverChange = { [weak self] hovering in
            Task { @MainActor in self?.handleHover(hovering) }
        }

        let hosting = FirstMouseHostingView(rootView: NotchRootView(controller: self, store: store))
        hosting.frame = host.bounds
        hosting.autoresizingMask = [.width, .height]
        host.addSubview(hosting)

        let handle = DragHandleView(frame: host.bounds)
        handle.onDragBegin = { [weak self] in
            Task { @MainActor in self?.beginDrag() }
        }
        handle.onDragChange = { [weak self] location in
            Task { @MainActor in self?.dragMoved(to: location) }
        }
        handle.onDragEnd = { [weak self] in
            Task { @MainActor in self?.endDrag() }
        }
        host.addSubview(handle, positioned: .above, relativeTo: hosting)

        panel.contentView = host
        panel.setFrame(frames.collapsed, display: true)
        panel.orderFrontRegardless()

        self.panel = panel
        self.hostView = host
        self.dragHandle = handle
        layoutDragHandle()
    }

    @objc private func screensChanged() {
        recomputeFrames()
        applyFrame(animated: false)
    }

    private func recomputeFrames() {
        frames = PlacementSolver.frames(
            for: placement,
            on: currentScreen,
            railItems: max(1, store.activeProviders.count)
        )
    }

    func relayout() {
        recomputeFrames()
        applyFrame(animated: true)
    }

    private func layoutDragHandle() {
        guard let host = hostView, let handle = dragHandle else { return }
        let bounds = host.bounds

        if !isExpanded {
            handle.frame = bounds
            return
        }

        switch frames.direction {
        case .down:
            let height = min(frames.stripHeight, bounds.height)
            handle.frame = NSRect(x: 0, y: bounds.height - height,
                                  width: bounds.width, height: height)
        case .up:
            let height = min(frames.stripHeight, bounds.height)
            handle.frame = NSRect(x: 0, y: 0, width: bounds.width, height: height)
        case .left:
            let width = min(frames.railWidth, bounds.width)
            handle.frame = NSRect(x: bounds.width - width, y: 0,
                                  width: width, height: bounds.height)
        case .right:
            let width = min(frames.railWidth, bounds.width)
            handle.frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        }
    }

    private func handleHover(_ hovering: Bool) {
        guard !isDragging else { return }
        collapseWorkItem?.cancel()

        if hovering {
            guard Date() >= suppressExpandUntil else { return }
            expand()
        } else {
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor in self?.collapse() }
            }
            collapseWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
        }
    }

    func expand() {
        guard !isExpanded, !isDragging else { return }
        shrinkWorkItem?.cancel()
        shrinkWorkItem = nil

        setFrameImmediately(frames.expanded)
        withAnimation(Reveal.open) { isExpanded = true }
        layoutDragHandle()

        store.refreshAll(manual: true)
    }

    func collapse() {
        guard isExpanded else { return }
        withAnimation(Reveal.close) { isExpanded = false }

        shrinkWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, !self.isExpanded else { return }
                self.setFrameImmediately(self.frames.collapsed)
            }
        }
        shrinkWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Reveal.settle, execute: work)
    }

    private func setFrameImmediately(_ target: NSRect) {
        guard let panel else { return }
        if panel.frame != target {
            panel.setFrame(target, display: true)
        }
        layoutDragHandle()
    }

    func toggle() {
        isExpanded ? collapse() : expand()
    }

    private func applyFrame(animated: Bool) {
        guard let panel else { return }
        let target = isExpanded ? frames.expanded : frames.collapsed
        guard panel.frame != target else {
            layoutDragHandle()
            return
        }

        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
                panel.animator().setFrame(target, display: true)
            }, completionHandler: { [weak self] in
                Task { @MainActor in self?.layoutDragHandle() }
            })
        } else {
            panel.setFrame(target, display: true)
            layoutDragHandle()
        }
    }

    private func beginDrag() {
        guard let panel else { return }
        isDragging = true
        collapseWorkItem?.cancel()

        if isExpanded {
            isExpanded = false
            applyFrame(animated: false)
        }

        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = panel.frame.origin
    }

    private func dragMoved(to location: CGPoint) {
        guard let panel,
              let startMouse = dragStartMouse,
              let startOrigin = dragStartOrigin else { return }

        panel.setFrameOrigin(CGPoint(
            x: startOrigin.x + (location.x - startMouse.x),
            y: startOrigin.y + (location.y - startMouse.y)
        ))
    }

    private func endDrag() {
        guard let panel else {
            isDragging = false
            return
        }
        isDragging = false
        dragStartMouse = nil
        dragStartOrigin = nil

        let screen = panel.screen ?? currentScreen
        var result = PlacementSolver.placement(fromCollapsed: panel.frame, on: screen)
        result = PlacementSolver.snapped(result, collapsed: panel.frame, on: screen)

        suppressExpandUntil = Date().addingTimeInterval(0.4)
        apply(placement: result, animated: true)
    }

    func apply(placement newPlacement: Placement, animated: Bool) {
        placement = newPlacement
        PlacementStore.save(newPlacement)
        recomputeFrames()
        applyFrame(animated: animated)
    }

    func resetPlacement() {
        let target: Placement = currentScreen.physicalNotchRect == nil ? .topCenter : .docked
        apply(placement: target, animated: true)
    }
}

enum PlacementStore {
    private static let modeKey = "placementMode"
    private static let xKey = "placementAnchorX"
    private static let yKey = "placementAnchorY"

    static func load() -> Placement {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: modeKey),
              let mode = DockMode(rawValue: raw) else {
            return .docked
        }
        return Placement(mode: mode,
                         anchorX: defaults.double(forKey: xKey),
                         anchorY: defaults.double(forKey: yKey))
    }

    static func save(_ placement: Placement) {
        let defaults = UserDefaults.standard
        defaults.set(placement.mode.rawValue, forKey: modeKey)
        defaults.set(placement.anchorX, forKey: xKey)
        defaults.set(placement.anchorY, forKey: yKey)
    }
}
