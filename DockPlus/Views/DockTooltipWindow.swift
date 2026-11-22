import AppKit
import Foundation

/// Floating label pill shown above/beside hovered dock items rendered in custom Clear Liquid Glass.
@MainActor
final class DockTooltipWindow {
    private let panel: NSPanel
    private let label: NSTextField
    private let glassView: LiquidGlassView
    private var isShown = false

    init() {
        let initialRect = NSRect(x: 0, y: 0, width: 120, height: 28)
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
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.alphaValue = 0

        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        label.textColor = NSColor.labelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle

        let rootView = NSView(frame: initialRect)
        rootView.autoresizingMask = [.width, .height]

        let glass = LiquidGlassView(frame: initialRect, cornerRadius: 14, variant: .floatingHUD)
        glass.autoresizingMask = [.width, .height]
        glass.contentView.addSubview(label)

        rootView.addSubview(glass)
        panel.contentView = rootView

        self.panel = panel
        self.label = label
        self.glassView = glass
    }

    func setGlassAppearance(transparency: Double, tintColor: DockConfig.TintColor?) {
        glassView.transparency = transparency
        glassView.tintColor = tintColor
    }

    func show(
        text: String,
        anchorScreenRect: CGRect,
        orientation: DockConfig.Orientation,
        snappedEdge: DockConfig.Edge?,
        screenBounds: CGRect
    ) {
        label.stringValue = text
        label.sizeToFit()

        let horizontalPad: CGFloat = 12
        let verticalPad: CGFloat = 5
        let pillWidth = min(max(label.frame.width + horizontalPad * 2, 44), 260)
        let pillHeight = max(label.frame.height + verticalPad * 2, 26)
        let gap: CGFloat = 10

        label.frame = NSRect(
            x: horizontalPad,
            y: (pillHeight - label.frame.height) / 2,
            width: pillWidth - horizontalPad * 2,
            height: label.frame.height
        )

        glassView.cornerRadius = pillHeight / 2

        let origin: CGPoint
        switch orientation {
        case .horizontal:
            let placeBelow = snappedEdge == .top || (anchorScreenRect.maxY + gap + pillHeight > screenBounds.maxY)
            let x = anchorScreenRect.midX - pillWidth / 2
            let y = placeBelow
                ? anchorScreenRect.minY - gap - pillHeight
                : anchorScreenRect.maxY + gap
            origin = CGPoint(x: x, y: y)
        case .vertical:
            let placeLeft = snappedEdge == .right || (anchorScreenRect.maxX + gap + pillWidth > screenBounds.maxX)
            let x = placeLeft
                ? anchorScreenRect.minX - gap - pillWidth
                : anchorScreenRect.maxX + gap
            let y = anchorScreenRect.midY - pillHeight / 2
            origin = CGPoint(x: x, y: y)
        }

        var frame = CGRect(origin: origin, size: CGSize(width: pillWidth, height: pillHeight))
        frame = DockGeometry.clamp(frame: frame, to: screenBounds.insetBy(dx: 6, dy: 6))

        if isShown {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.06
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
            isShown = true
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.10
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1.0
            }
        }
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.09
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak panel] in
            Task { @MainActor in
                if let panel, panel.alphaValue < 0.05 {
                    panel.orderOut(nil)
                }
            }
        })
    }

    func close() {
        isShown = false
        panel.orderOut(nil)
        panel.close()
    }
}
