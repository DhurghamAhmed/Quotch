import AppKit

enum NotchMetrics {
    static let wingWidth: CGFloat = 116
    static let pillWidth: CGFloat = 240
    static let pillHeight: CGFloat = 44

    static let railWidth: CGFloat = 68
    static let railItemHeight: CGFloat = 64
    static let railPadding: CGFloat = 8

    static let expandedWidth: CGFloat = 380
    static let preferredCardHeight: CGFloat = 410
    static let minCardHeight: CGFloat = 170

    static let edgeMargin: CGFloat = 12
    static let edgeSnapDistance: CGFloat = 40
    static let notchSnapDistance: CGFloat = 90
    static let edgeAnchorTolerance: Double = 0.08

    static let notchCornerRadius: CGFloat = 13
    static let cardCornerRadius: CGFloat = 24
    static let railCornerRadius: CGFloat = 20
}

enum DockMode: String {
    case notch
    case free
}

enum ExpandDirection {
    case down
    case up
    case left
    case right

    var isHorizontal: Bool { self == .left || self == .right }
}

struct Placement: Equatable {
    var mode: DockMode
    var anchorX: Double
    var anchorY: Double

    static let docked = Placement(mode: .notch, anchorX: 0.5, anchorY: 0)

    static let topLeft      = Placement(mode: .free, anchorX: 0.00, anchorY: 0.00)
    static let topCenter    = Placement(mode: .free, anchorX: 0.50, anchorY: 0.00)
    static let topRight     = Placement(mode: .free, anchorX: 1.00, anchorY: 0.00)
    static let leftMiddle   = Placement(mode: .free, anchorX: 0.00, anchorY: 0.50)
    static let rightMiddle  = Placement(mode: .free, anchorX: 1.00, anchorY: 0.50)
    static let bottomLeft   = Placement(mode: .free, anchorX: 0.00, anchorY: 1.00)
    static let bottomRight  = Placement(mode: .free, anchorX: 1.00, anchorY: 1.00)

    var isEdgeParked: Bool {
        guard mode == .free else { return false }
        return anchorX <= NotchMetrics.edgeAnchorTolerance
            || anchorX >= 1 - NotchMetrics.edgeAnchorTolerance
    }

    var isRightEdge: Bool { anchorX >= 0.5 }

    var parkedLeft: Bool {
        mode == .free && anchorX <= NotchMetrics.edgeAnchorTolerance
    }
    var parkedRight: Bool {
        mode == .free && anchorX >= 1 - NotchMetrics.edgeAnchorTolerance
    }
    var parkedTop: Bool {
        mode == .free && anchorY <= NotchMetrics.edgeAnchorTolerance
    }
    var parkedBottom: Bool {
        mode == .free && anchorY >= 1 - NotchMetrics.edgeAnchorTolerance
    }
}

struct CornerRounding: Equatable {
    var topLeft: Bool
    var topRight: Bool
    var bottomLeft: Bool
    var bottomRight: Bool

    static let all = CornerRounding(topLeft: true, topRight: true,
                                    bottomLeft: true, bottomRight: true)
    static let bottomOnly = CornerRounding(topLeft: false, topRight: false,
                                           bottomLeft: true, bottomRight: true)
}

struct PanelFrames: Equatable {
    var collapsed: NSRect
    var expanded: NSRect
    var direction: ExpandDirection
    var stripHeight: CGFloat
    var railWidth: CGFloat
    var isNotchDocked: Bool
    var isRail: Bool
    var notchWidth: CGFloat
    var corners: CornerRounding

    var expandsDownward: Bool { direction == .down }
}

extension NSScreen {
    var physicalNotchRect: NSRect? {
        guard safeAreaInsets.top > 0 else { return nil }
        guard let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return nil }
        let width = frame.width - left.width - right.width
        guard width > 1 else { return nil }
        return NSRect(x: frame.minX + left.width,
                      y: frame.maxY - safeAreaInsets.top,
                      width: width,
                      height: safeAreaInsets.top)
    }
}

enum PlacementSolver {

    static func frames(for placement: Placement,
                       on screen: NSScreen,
                       railItems: Int) -> PanelFrames {
        if placement.mode == .notch, let notch = screen.physicalNotchRect {
            return dockedFrames(notch: notch, screen: screen)
        }
        let effective = placement.mode == .notch ? Placement.topCenter : placement

        if effective.isEdgeParked {
            return railFrames(placement: effective, screen: screen, items: max(1, railItems))
        }
        return pillFrames(placement: effective, screen: screen)
    }

    private static func dockedFrames(notch: NSRect, screen: NSScreen) -> PanelFrames {
        let stripHeight = notch.height
        let collapsedWidth = notch.width + NotchMetrics.wingWidth * 2

        let collapsed = NSRect(
            x: (screen.frame.midX - collapsedWidth / 2).rounded(),
            y: (screen.frame.maxY - stripHeight).rounded(),
            width: collapsedWidth.rounded(),
            height: stripHeight.rounded()
        )

        let expandedWidth = max(NotchMetrics.expandedWidth, collapsedWidth)
        let room = screen.visibleFrame.height - NotchMetrics.edgeMargin
        let cardHeight = max(NotchMetrics.minCardHeight,
                             min(NotchMetrics.preferredCardHeight, room))
        let expandedHeight = cardHeight + stripHeight

        let expanded = NSRect(
            x: (screen.frame.midX - expandedWidth / 2).rounded(),
            y: (screen.frame.maxY - expandedHeight).rounded(),
            width: expandedWidth,
            height: expandedHeight
        )

        return PanelFrames(collapsed: collapsed,
                           expanded: expanded,
                           direction: .down,
                           stripHeight: stripHeight,
                           railWidth: 0,
                           isNotchDocked: true,
                           isRail: false,
                           notchWidth: notch.width,
                           corners: .bottomOnly)
    }

    private static func pillFrames(placement: Placement, screen: NSScreen) -> PanelFrames {
        let visible = screen.visibleFrame
        let width = NotchMetrics.pillWidth
        let height = NotchMetrics.pillHeight
        let margin = NotchMetrics.edgeMargin

        var x: CGFloat
        if placement.parkedLeft {
            x = visible.minX
        } else if placement.parkedRight {
            x = visible.maxX - width
        } else {
            let centreX = visible.minX + CGFloat(placement.anchorX) * visible.width
            x = clamp(centreX - width / 2, visible.minX + margin,
                      max(visible.minX + margin, visible.maxX - width - margin))
        }

        var top: CGFloat
        if placement.parkedTop {
            top = screen.frame.maxY
        } else if placement.parkedBottom {
            top = visible.minY + height
        } else {
            top = clamp(visible.maxY - CGFloat(placement.anchorY) * visible.height,
                        visible.minY + height + margin, visible.maxY - margin)
        }

        let collapsed = NSRect(x: x.rounded(), y: (top - height).rounded(),
                               width: width, height: height)

        let expandedWidth = max(NotchMetrics.expandedWidth, width)
        var ex: CGFloat
        if placement.parkedLeft {
            ex = collapsed.minX
        } else if placement.parkedRight {
            ex = collapsed.maxX - expandedWidth
        } else {
            ex = collapsed.midX - expandedWidth / 2
        }
        ex = clamp(ex, visible.minX, max(visible.minX, visible.maxX - expandedWidth))

        let spaceBelow = collapsed.minY - (visible.minY + margin)
        let spaceAbove = (visible.maxY - margin) - collapsed.maxY

        var direction = ExpandDirection.down
        var available = spaceBelow
        if spaceBelow < NotchMetrics.minCardHeight && spaceAbove > spaceBelow {
            direction = .up
            available = spaceAbove
        }

        let cardHeight = max(NotchMetrics.minCardHeight,
                             min(NotchMetrics.preferredCardHeight, available))
        let expandedHeight = cardHeight + height

        var ey = direction == .down ? collapsed.maxY - expandedHeight : collapsed.minY
        ey = max(ey, visible.minY + margin)
        let ceiling = max(visible.maxY - margin, collapsed.maxY)
        if ey + expandedHeight > ceiling {
            ey = max(visible.minY + margin, ceiling - expandedHeight)
        }

        let expanded = NSRect(x: ex.rounded(), y: ey.rounded(),
                              width: expandedWidth, height: expandedHeight)

        return PanelFrames(collapsed: collapsed,
                           expanded: expanded,
                           direction: direction,
                           stripHeight: height,
                           railWidth: 0,
                           isNotchDocked: false,
                           isRail: false,
                           notchWidth: 0,
                           corners: rounding(for: collapsed, on: screen))
    }

    private static func railFrames(placement: Placement, screen: NSScreen, items: Int) -> PanelFrames {
        let visible = screen.visibleFrame
        let margin = NotchMetrics.edgeMargin
        let width = NotchMetrics.railWidth
        let height = CGFloat(items) * NotchMetrics.railItemHeight + NotchMetrics.railPadding * 2

        let onRight = placement.isRightEdge
        let x = onRight ? visible.maxX - width : visible.minX

        var top = visible.maxY - CGFloat(placement.anchorY) * visible.height
        top = clamp(top, visible.minY + height + margin, visible.maxY - margin)

        let collapsed = NSRect(x: x.rounded(), y: (top - height).rounded(),
                               width: width, height: height)

        let roomForCard = visible.width - width - margin * 2
        let cardWidth = max(220, min(NotchMetrics.expandedWidth, roomForCard))
        let cardHeight = max(NotchMetrics.minCardHeight,
                             min(NotchMetrics.preferredCardHeight, visible.height - margin * 2))

        let expandedWidth = cardWidth + width
        let ex = onRight ? collapsed.maxX - expandedWidth : collapsed.minX

        let lowerBound = max(visible.minY + margin, collapsed.maxY - cardHeight)
        let upperBound = min(visible.maxY - margin - cardHeight, collapsed.minY)
        var ey = collapsed.midY - cardHeight / 2
        if lowerBound <= upperBound {
            ey = clamp(ey, lowerBound, upperBound)
        } else {
            ey = clamp(ey, visible.minY + margin,
                       max(visible.minY + margin, visible.maxY - margin - cardHeight))
        }

        let expanded = NSRect(x: ex.rounded(), y: ey.rounded(),
                              width: expandedWidth, height: cardHeight)

        return PanelFrames(collapsed: collapsed,
                           expanded: expanded,
                           direction: onRight ? .left : .right,
                           stripHeight: 0,
                           railWidth: width,
                           isNotchDocked: false,
                           isRail: true,
                           notchWidth: 0,
                           corners: rounding(for: collapsed, on: screen))
    }

    private static func rounding(for rect: NSRect, on screen: NSScreen) -> CornerRounding {
        let full = screen.frame
        let visible = screen.visibleFrame
        let epsilon: CGFloat = 1.5

        let touchesTop = rect.maxY >= full.maxY - epsilon
        let touchesBottom = rect.minY <= visible.minY + epsilon
        let touchesLeft = rect.minX <= visible.minX + epsilon
        let touchesRight = rect.maxX >= visible.maxX - epsilon

        return CornerRounding(
            topLeft: !(touchesTop || touchesLeft),
            topRight: !(touchesTop || touchesRight),
            bottomLeft: !(touchesBottom || touchesLeft),
            bottomRight: !(touchesBottom || touchesRight)
        )
    }

    static func placement(fromCollapsed rect: NSRect, on screen: NSScreen) -> Placement {
        let visible = screen.visibleFrame
        let anchorX = Double((rect.midX - visible.minX) / max(1, visible.width))
        let anchorY = Double((visible.maxY - rect.maxY) / max(1, visible.height))
        return Placement(mode: .free,
                         anchorX: clamp(anchorX, 0, 1),
                         anchorY: clamp(anchorY, 0, 1))
    }

    static func snapped(_ placement: Placement, collapsed: NSRect, on screen: NSScreen) -> Placement {
        if let notch = screen.physicalNotchRect {
            let dx = abs(collapsed.midX - notch.midX)
            let dy = abs(collapsed.midY - notch.midY)
            if dx < NotchMetrics.notchSnapDistance && dy < NotchMetrics.notchSnapDistance {
                return .docked
            }
        }

        let visible = screen.visibleFrame
        var result = placement

        if collapsed.minX - visible.minX < NotchMetrics.edgeSnapDistance {
            result.anchorX = 0
        } else if visible.maxX - collapsed.maxX < NotchMetrics.edgeSnapDistance {
            result.anchorX = 1
        }

        if visible.maxY - collapsed.maxY < NotchMetrics.edgeSnapDistance {
            result.anchorY = 0
        } else if collapsed.minY - visible.minY < NotchMetrics.edgeSnapDistance {
            result.anchorY = 1
        }

        return result
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        min(max(value, low), high)
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(max(value, low), high)
    }
}
