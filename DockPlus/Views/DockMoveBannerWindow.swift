import AppKit
import Foundation

/// Floating Move Mode banner shown above a dock rendered in custom Clear Liquid Glass.
@MainActor
final class DockMoveBannerWindow {
    private let panel: NSPanel
    private let glassView: LiquidGlassView
    private let contentStack: NSStackView
    private var escMonitor: Any?
    var onDone: (() -> Void)?

    init() {
        let initialRect = NSRect(x: 0, y: 0, width: 210, height: 34)
        let panel = NSPanel(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none

        let rootView = NSView(frame: initialRect)
        rootView.autoresizingMask = [.width, .height]

        let iconView = NSImageView()
        let symConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right", accessibilityDescription: "Move")?
            .withSymbolConfiguration(symConfig)
        iconView.contentTintColor = .labelColor

        let label = NSTextField(labelWithString: "Drag dock to move")
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor

        let doneButton = NSButton(title: "Done", target: nil, action: nil)
        doneButton.bezelStyle = .rounded
        doneButton.controlSize = .small
        doneButton.keyEquivalent = "\r"

        let stack = NSStackView(views: [iconView, label, doneButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 12, bottom: 5, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let glass = LiquidGlassView(frame: initialRect, cornerRadius: 17, variant: .floatingHUD)
        glass.autoresizingMask = [.width, .height]
        glass.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: glass.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor)
        ])

        rootView.addSubview(glass)
        panel.contentView = rootView

        self.panel = panel
        self.glassView = glass
        self.contentStack = stack

        doneButton.target = self
        doneButton.action = #selector(doneClicked)
    }

    func setGlassAppearance(transparency: Double, tintColor: DockConfig.TintColor?) {
        glassView.transparency = transparency
        glassView.tintColor = tintColor
    }

    func show(near pillScreenRect: CGRect, orientation: DockConfig.Orientation, snappedEdge: DockConfig.Edge?, screenBounds: CGRect) {
        let fitting = contentStack.fittingSize
        let size = CGSize(width: max(fitting.width, 200), height: max(fitting.height, 34))
        glassView.cornerRadius = size.height / 2

        let gap: CGFloat = 12
        let origin: CGPoint
        switch orientation {
        case .horizontal:
            let placeBelow = snappedEdge == .top || (pillScreenRect.maxY + gap + size.height > screenBounds.maxY)
            origin = CGPoint(
                x: pillScreenRect.midX - size.width / 2,
                y: placeBelow ? pillScreenRect.minY - gap - size.height : pillScreenRect.maxY + gap
            )
        case .vertical:
            let placeLeft = snappedEdge == .right || (pillScreenRect.maxX + gap + size.width > screenBounds.maxX)
            origin = CGPoint(
                x: placeLeft ? pillScreenRect.minX - gap - size.width : pillScreenRect.maxX + gap,
                y: pillScreenRect.midY - size.height / 2
            )
        }

        let frame = DockGeometry.clamp(frame: CGRect(origin: origin, size: size), to: screenBounds.insetBy(dx: 8, dy: 8))
        panel.setFrame(frame, display: true)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        installEscMonitorIfNeeded()
    }

    func hide() {
        removeEscMonitor()
        panel.orderOut(nil)
    }

    func close() {
        removeEscMonitor()
        panel.orderOut(nil)
        panel.close()
    }

    @objc private func doneClicked() {
        onDone?()
    }

    private func installEscMonitorIfNeeded() {
        guard escMonitor == nil else { return }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.onDone?()
                return nil
            }
            return event
        }
    }

    private func removeEscMonitor() {
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
    }
}
