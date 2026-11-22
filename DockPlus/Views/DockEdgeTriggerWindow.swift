import AppKit
import Foundation

/// Completely invisible 2 pt screen-edge trigger strip used while a snapped dock is auto-hidden.
/// Has zero visible pixels, zero shadow, zero polling (uses NSTrackingArea only), and cancels
/// pending reveals on mouse exit so crossing a shared multi-monitor seam does not misfire.
@MainActor
final class DockEdgeTriggerWindow {
    private let panel: NSPanel
    private let triggerView: EdgeTriggerView

    var onMouseEntered: (() -> Void)? {
        didSet { triggerView.onMouseEntered = onMouseEntered }
    }

    var onMouseExited: (() -> Void)? {
        didSet { triggerView.onMouseExited = onMouseExited }
    }

    init() {
        let initialRect = NSRect(x: 0, y: 0, width: 100, height: 2)
        let panel = NSPanel(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.animationBehavior = .none

        let view = EdgeTriggerView(frame: initialRect)
        view.autoresizingMask = [.width, .height]
        panel.contentView = view

        self.panel = panel
        self.triggerView = view
    }

    func show(
        for edge: DockConfig.Edge,
        visibleDockFrame: CGRect,
        visibleFrame: CGRect,
        screenFrame: CGRect
    ) {
        let thickness: CGFloat = 2
        let rawRect: CGRect
        switch edge {
        case .bottom:
            rawRect = CGRect(
                x: visibleDockFrame.minX,
                y: screenFrame.minY,
                width: visibleDockFrame.width,
                height: thickness
            )
        case .top:
            // When a menu bar occupies the top of this monitor, sit flush right below it so the
            // trigger is reachable without colliding with macOS menu bar tracking.
            let topEdgeY = (screenFrame.maxY - visibleFrame.maxY > 4) ? visibleFrame.maxY : screenFrame.maxY
            rawRect = CGRect(
                x: visibleDockFrame.minX,
                y: topEdgeY - thickness,
                width: visibleDockFrame.width,
                height: thickness
            )
        case .left:
            rawRect = CGRect(
                x: screenFrame.minX,
                y: visibleDockFrame.minY,
                width: thickness,
                height: visibleDockFrame.height
            )
        case .right:
            rawRect = CGRect(
                x: screenFrame.maxX - thickness,
                y: visibleDockFrame.minY,
                width: thickness,
                height: visibleDockFrame.height
            )
        }

        // Clamp strictly within this display so the trigger never overhangs onto an adjacent monitor.
        let triggerRect = rawRect.intersection(screenFrame)
        guard !triggerRect.isNull, triggerRect.width > 0, triggerRect.height > 0 else { return }

        panel.setFrame(triggerRect, display: false)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        panel.orderOut(nil)
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }
}

private final class EdgeTriggerView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }
}
