import CoreGraphics
import Foundation

struct DockEdgeInsets: Equatable {
    var top: CGFloat
    var bottom: CGFloat
    var left: CGFloat
    var right: CGFloat

    static let zero = DockEdgeInsets(top: 0, bottom: 0, left: 0, right: 0)
}

/// Pure geometry calculations for dock sizing, snapping, clamping, magnification headroom, and auto-hide positioning.
enum DockGeometry {
    static let snapThreshold: CGFloat = 24
    static let edgeInset: CGFloat = 8
    static let autoHideSliver: CGFloat = 2
    static let paddingAlongAxis: CGFloat = 12
    static let paddingCrossAxis: CGFloat = 6
    static let itemSpacing: CGFloat = 7
    static let runningDotSpace: CGFloat = 7
    static let separatorThickness: CGFloat = 17
    static let emptyDockLength: CGFloat = 172

    /// Resting visual glass pill size for `config` (optionally including transient open apps).
    static func panelSize(for config: DockConfig, displayedItems: [DockItem]? = nil) -> CGSize {
        let items = displayedItems ?? config.items
        let iconSize = CGFloat(config.iconSize)
        let crossAxis = iconSize + runningDotSpace + paddingCrossAxis * 2

        let contentLength: CGFloat
        if items.isEmpty {
            contentLength = emptyDockLength
        } else {
            var total: CGFloat = 0
            for (index, item) in items.enumerated() {
                if index > 0 {
                    total += itemSpacing
                }
                total += item.kind == .separator ? separatorThickness : iconSize
            }
            contentLength = total + paddingAlongAxis * 2
        }

        switch config.effectiveOrientation {
        case .horizontal:
            return CGSize(width: max(contentLength, crossAxis), height: crossAxis)
        case .vertical:
            return CGSize(width: crossAxis, height: max(contentLength, crossAxis))
        }
    }

    /// Extra transparent headroom around the glass pill so magnified icons bloom out smoothly without clipping.
    static func magnificationHeadroom(for config: DockConfig, displayedItemCount: Int? = nil) -> DockEdgeInsets {
        let count = displayedItemCount ?? config.items.count
        guard config.magnificationEnabled, count > 0 else {
            return DockEdgeInsets(top: 12, bottom: 12, left: 12, right: 12)
        }

        let iconSize = CGFloat(config.iconSize)
        let extraCross = ceil(iconSize * CGFloat(config.magnificationScale - 1.0)) + 20
        let extraAlong = ceil(iconSize * CGFloat(config.magnificationScale - 1.0) * 2.2) + 20

        switch config.effectiveOrientation {
        case .horizontal:
            let bloomsDown = config.placement.snappedEdge == .top
            return DockEdgeInsets(
                top: bloomsDown ? 12 : extraCross,
                bottom: bloomsDown ? extraCross : 12,
                left: extraAlong,
                right: extraAlong
            )
        case .vertical:
            let bloomsLeft = config.placement.snappedEdge == .right
            return DockEdgeInsets(
                top: extraAlong,
                bottom: extraAlong,
                left: bloomsLeft ? extraCross : 12,
                right: bloomsLeft ? 12 : extraCross
            )
        }
    }

    static func windowFrame(forPillFrame pillFrame: CGRect, insets: DockEdgeInsets) -> CGRect {
        CGRect(
            x: pillFrame.origin.x - insets.left,
            y: pillFrame.origin.y - insets.bottom,
            width: pillFrame.width + insets.left + insets.right,
            height: pillFrame.height + insets.top + insets.bottom
        )
    }

    static func pillFrame(fromWindowFrame windowFrame: CGRect, insets: DockEdgeInsets) -> CGRect {
        CGRect(
            x: windowFrame.origin.x + insets.left,
            y: windowFrame.origin.y + insets.bottom,
            width: max(windowFrame.width - insets.left - insets.right, 1),
            height: max(windowFrame.height - insets.top - insets.bottom, 1)
        )
    }

    /// Clamps a dock panel's window frame strictly inside `displayBounds` so transparent
    /// magnification headroom, shadows, and slide animations never bleed onto adjacent monitors.
    static func clippedWindowLayout(
        forPillFrame pillFrame: CGRect,
        desiredInsets: DockEdgeInsets,
        within displayBounds: CGRect
    ) -> (windowFrame: CGRect, insets: DockEdgeInsets) {
        let rawWindow = windowFrame(forPillFrame: pillFrame, insets: desiredInsets)
        let clipped = rawWindow.intersection(displayBounds)
        guard !clipped.isNull, clipped.width >= pillFrame.width - 1, clipped.height >= pillFrame.height - 1 else {
            return (pillFrame, .zero)
        }
        let adjustedInsets = DockEdgeInsets(
            top: max(clipped.maxY - pillFrame.maxY, 0),
            bottom: max(pillFrame.minY - clipped.minY, 0),
            left: max(pillFrame.minX - clipped.minX, 0),
            right: max(clipped.maxX - pillFrame.maxX, 0)
        )
        return (clipped, adjustedInsets)
    }

    /// Local slide offset inside the display-clipped window for smooth appear/retreat animations.
    /// Because the panel stays strictly within its display frame, sliding the inner stage past
    /// the clipped edge hides the dock seamlessly at the monitor seam without bleeding onto neighbors.
    static func retreatedStageOffset(
        for edge: DockConfig.Edge?,
        pillFrameInWindow: CGRect,
        windowSize: CGSize
    ) -> CGPoint {
        let margin: CGFloat = 14
        switch edge {
        case .bottom:
            return CGPoint(x: 0, y: -(pillFrameInWindow.maxY + margin))
        case .top:
            return CGPoint(x: 0, y: (windowSize.height - pillFrameInWindow.minY) + margin)
        case .left:
            return CGPoint(x: -(pillFrameInWindow.maxX + margin), y: 0)
        case .right:
            return CGPoint(x: (windowSize.width - pillFrameInWindow.minX) + margin, y: 0)
        case nil:
            return CGPoint(x: 0, y: -16)
        }
    }

    static func cornerRadius(for size: CGSize) -> CGFloat {
        min(min(size.width, size.height) * 0.34, 24)
    }

    static func visibleFrame(
        for placement: DockConfig.Placement,
        panelSize: CGSize,
        in visibleFrame: CGRect
    ) -> CGRect {
        let rawOrigin: CGPoint
        switch placement {
        case .floating(let x, let y, _):
            rawOrigin = CGPoint(x: x, y: y)
        case .snapped(let edge, let offset, _):
            switch edge {
            case .bottom:
                let x = visibleFrame.midX - panelSize.width / 2 + CGFloat(offset)
                let y = visibleFrame.minY + edgeInset
                rawOrigin = CGPoint(x: x, y: y)
            case .top:
                let x = visibleFrame.midX - panelSize.width / 2 + CGFloat(offset)
                let y = visibleFrame.maxY - panelSize.height - edgeInset
                rawOrigin = CGPoint(x: x, y: y)
            case .left:
                let x = visibleFrame.minX + edgeInset
                let y = visibleFrame.midY - panelSize.height / 2 + CGFloat(offset)
                rawOrigin = CGPoint(x: x, y: y)
            case .right:
                let x = visibleFrame.maxX - panelSize.width - edgeInset
                let y = visibleFrame.midY - panelSize.height / 2 + CGFloat(offset)
                rawOrigin = CGPoint(x: x, y: y)
            }
        }
        return clamp(frame: CGRect(origin: rawOrigin, size: panelSize), to: visibleFrame)
    }

    static let autoHideOffscreenGap: CGFloat = 10

    static func autoHiddenFrame(
        for edge: DockConfig.Edge,
        visibleDockFrame: CGRect,
        screenFrame: CGRect
    ) -> CGRect {
        var frame = visibleDockFrame
        switch edge {
        case .bottom:
            frame.origin.y = screenFrame.minY - frame.height - autoHideOffscreenGap
        case .top:
            frame.origin.y = screenFrame.maxY + autoHideOffscreenGap
        case .left:
            frame.origin.x = screenFrame.minX - frame.width - autoHideOffscreenGap
        case .right:
            frame.origin.x = screenFrame.maxX + autoHideOffscreenGap
        }
        return frame
    }

    static func clamp(frame: CGRect, to bounds: CGRect) -> CGRect {
        var result = frame
        if result.width >= bounds.width {
            result.origin.x = bounds.minX
        } else {
            result.origin.x = min(max(result.origin.x, bounds.minX), bounds.maxX - result.width)
        }
        if result.height >= bounds.height {
            result.origin.y = bounds.minY
        } else {
            result.origin.y = min(max(result.origin.y, bounds.minY), bounds.maxY - result.height)
        }
        return result
    }

    static func placementForDraggedFrame(
        _ frame: CGRect,
        in visibleFrame: CGRect,
        displayUUID: String?,
        threshold: CGFloat = snapThreshold
    ) -> DockConfig.Placement {
        let distBottom = abs(frame.minY - visibleFrame.minY)
        let distTop = abs(visibleFrame.maxY - frame.maxY)
        let distLeft = abs(frame.minX - visibleFrame.minX)
        let distRight = abs(visibleFrame.maxX - frame.maxX)

        let candidates: [(DockConfig.Edge, CGFloat)] = [
            (.bottom, distBottom),
            (.top, distTop),
            (.left, distLeft),
            (.right, distRight)
        ]

        if let nearest = candidates.min(by: { $0.1 < $1.1 }), nearest.1 <= threshold {
            let offset: Double
            switch nearest.0 {
            case .bottom, .top:
                offset = Double(frame.midX - visibleFrame.midX)
            case .left, .right:
                offset = Double(frame.midY - visibleFrame.midY)
            }
            return .snapped(edge: nearest.0, offset: offset, displayUUID: displayUUID)
        }

        let clamped = clamp(frame: frame, to: visibleFrame)
        return .floating(x: Double(clamped.origin.x), y: Double(clamped.origin.y), displayUUID: displayUUID)
    }
}
