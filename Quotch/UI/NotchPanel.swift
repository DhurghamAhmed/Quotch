import AppKit
import SwiftUI

final class NotchPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true
        appearance = NSAppearance(named: .vibrantDark)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { false }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class DragHandleView: NSView {

    var onDragBegin: (() -> Void)?
    var onDragChange: ((CGPoint) -> Void)?
    var onDragEnd: (() -> Void)?

    private var isDragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        if !isDragging {
            isDragging = true
            onDragBegin?()
        }
        onDragChange?(NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            onDragEnd?()
        }
        isDragging = false
    }

    override func rightMouseDown(with event: NSEvent) {
        super.rightMouseDown(with: event)
    }
}

final class HoverHostView: NSView {

    var onHoverChange: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?
    private(set) var isHovering = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area

        let pointInWindow = window?.mouseLocationOutsideOfEventStream ?? .zero
        let inside = bounds.contains(convert(pointInWindow, from: nil))
        if inside != isHovering {
            isHovering = inside
            onHoverChange?(inside)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isHovering else { return }
        isHovering = true
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        guard isHovering else { return }
        isHovering = false
        onHoverChange?(false)
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
    }
}
