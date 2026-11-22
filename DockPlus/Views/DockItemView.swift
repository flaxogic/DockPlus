import AppKit
import Foundation

@MainActor
protocol DockItemViewDelegate: AnyObject {
    func dockItemViewDidClick(_ view: DockItemView)
    func dockItemView(_ view: DockItemView, didRequestContextMenu event: NSEvent)
    func dockItemViewDidBeginDrag(_ view: DockItemView, event: NSEvent)
    func dockItemView(_ view: DockItemView, didDrag event: NSEvent)
    func dockItemViewDidEndDrag(_ view: DockItemView, event: NSEvent)
}

@MainActor
final class DockItemView: NSView {
    let item: DockItem
    let isTransientOpenApp: Bool
    let isAutoDivider: Bool

    private(set) var orientation: DockConfig.Orientation
    private(set) var baseIconSize: CGFloat
    private(set) var renderIconSize: CGFloat
    private(set) var isRunning: Bool = false
    private(set) var dotOnOppositeSide: Bool = false

    weak var delegate: DockItemViewDelegate?

    private let iconLayer = CALayer()
    private let dotLayer = CALayer()
    private let separatorHighlightLayer = CALayer()
    private let separatorLayer = CALayer()

    private var isPressed = false
    private var isSeparatorHovered = false
    private var mouseDownLocation: NSPoint = .zero
    private var isDraggingItem = false

    var isDraggableItem: Bool {
        !isTransientOpenApp && !isAutoDivider
    }

    init(
        item: DockItem,
        orientation: DockConfig.Orientation,
        baseIconSize: CGFloat,
        renderIconSize: CGFloat,
        isRunning: Bool,
        dotOnOppositeSide: Bool,
        isTransientOpenApp: Bool = false,
        isAutoDivider: Bool = false
    ) {
        self.item = item
        self.orientation = orientation
        self.baseIconSize = baseIconSize
        self.renderIconSize = renderIconSize
        self.isRunning = isRunning
        self.dotOnOppositeSide = dotOnOppositeSide
        self.isTransientOpenApp = isTransientOpenApp
        self.isAutoDivider = isAutoDivider
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        setupLayers()
        updateContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateContent()
        updateAppearanceColors()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContent()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearanceColors()
    }

    func update(
        orientation: DockConfig.Orientation,
        baseIconSize: CGFloat,
        renderIconSize: CGFloat,
        isRunning: Bool,
        dotOnOppositeSide: Bool
    ) {
        let needsReload = abs(self.renderIconSize - renderIconSize) > 0.5
        self.orientation = orientation
        self.baseIconSize = baseIconSize
        self.renderIconSize = renderIconSize
        self.isRunning = isRunning
        self.dotOnOppositeSide = dotOnOppositeSide
        if needsReload {
            updateContent()
        } else {
            dotLayer.isHidden = !(item.kind == .app && isRunning)
        }
        needsLayout = true
    }

    func setRunning(_ running: Bool) {
        guard isRunning != running else { return }
        isRunning = running
        let shouldShow = item.kind == .app && isRunning
        if shouldShow {
            dotLayer.isHidden = false
            dotLayer.opacity = 1.0
            let pop = CASpringAnimation(keyPath: "transform.scale")
            pop.fromValue = 0.2
            pop.toValue = 1.0
            pop.damping = 14
            pop.stiffness = 280
            pop.duration = pop.settlingDuration
            dotLayer.add(pop, forKey: "dotPop")
        } else {
            dotLayer.isHidden = true
        }
    }

    func setSeparatorHovered(_ hovered: Bool) {
        guard item.kind == .separator, !isAutoDivider, isSeparatorHovered != hovered else { return }
        isSeparatorHovered = hovered
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        separatorHighlightLayer.opacity = hovered ? 1.0 : 0.0
        CATransaction.commit()
    }

    func setDragLifted(_ lifted: Bool) {
        let targetScale: CGFloat = lifted ? 1.08 : 1.0
        let transform = CATransform3DMakeScale(targetScale, targetScale, 1.0)
        let spring = CASpringAnimation(keyPath: "transform")
        let targetLayer = item.kind == .separator ? separatorLayer : iconLayer
        spring.fromValue = targetLayer.presentation()?.transform ?? targetLayer.transform
        spring.toValue = transform
        spring.damping = 18
        spring.stiffness = 340
        spring.duration = spring.settlingDuration

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        targetLayer.transform = transform
        CATransaction.commit()
        targetLayer.add(spring, forKey: "liftSpring")
    }

    func playLaunchBounce() {
        guard item.kind == .app else { return }
        let keyPath = orientation == .horizontal ? "transform.translation.y" : "transform.translation.x"
        let sign: CGFloat = dotOnOppositeSide ? -1 : 1
        let bounce = CAKeyframeAnimation(keyPath: keyPath)
        bounce.values = [0, 12 * sign, 0, 7 * sign, 0]
        bounce.keyTimes = [0, 0.28, 0.54, 0.78, 1.0]
        bounce.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeIn),
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeIn)
        ]
        bounce.duration = 0.62
        iconLayer.add(bounce, forKey: "launchBounce")
    }

    private func setupLayers() {
        guard let rootLayer = layer else { return }

        if item.kind == .separator {
            separatorHighlightLayer.cornerRadius = 6
            separatorHighlightLayer.opacity = 0
            rootLayer.addSublayer(separatorHighlightLayer)

            separatorLayer.cornerRadius = 0.75
            rootLayer.addSublayer(separatorLayer)
        } else {
            iconLayer.contentsGravity = .resizeAspect
            iconLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            iconLayer.shadowColor = NSColor.black.cgColor
            iconLayer.shadowOpacity = 0.20
            iconLayer.shadowRadius = 4
            iconLayer.shadowOffset = CGSize(width: 0, height: -2)
            rootLayer.addSublayer(iconLayer)

            dotLayer.cornerRadius = 2.0
            dotLayer.shadowColor = NSColor.black.cgColor
            dotLayer.shadowOpacity = 0.35
            dotLayer.shadowRadius = 1.5
            dotLayer.shadowOffset = .zero
            dotLayer.isHidden = true
            rootLayer.addSublayer(dotLayer)
        }
        updateAppearanceColors()
    }

    private func updateAppearanceColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            separatorHighlightLayer.backgroundColor = NSColor.labelColor.withAlphaComponent(0.10).cgColor
            separatorLayer.backgroundColor = NSColor.labelColor.withAlphaComponent(isAutoDivider ? 0.22 : 0.32).cgColor
            dotLayer.backgroundColor = NSColor.labelColor.withAlphaComponent(0.92).cgColor
        }
    }

    private func updateContent() {
        guard item.kind != .separator else { return }

        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        iconLayer.contentsScale = scale

        if let path = item.path {
            let exists = item.existsOnDisk
            if let cgImage = IconCache.shared.cgIcon(for: path, size: renderIconSize, scale: scale) {
                iconLayer.contents = cgImage
            } else {
                iconLayer.contents = IconCache.shared.icon(for: path, size: renderIconSize, scale: scale)
            }
            iconLayer.opacity = exists ? 1.0 : 0.45
        } else {
            iconLayer.contents = IconCache.missingItemIcon(size: renderIconSize)
            iconLayer.opacity = 0.45
        }

        dotLayer.isHidden = !(item.kind == .app && isRunning)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if item.kind == .separator {
            let length = baseIconSize * 0.68
            switch orientation {
            case .horizontal:
                separatorHighlightLayer.frame = CGRect(
                    x: 2,
                    y: (bounds.height - length) / 2 - 2 + (dotOnOppositeSide ? -2 : 2),
                    width: max(bounds.width - 4, 8),
                    height: length + 4
                )
                separatorLayer.frame = CGRect(
                    x: (bounds.width - 1.5) / 2,
                    y: (bounds.height - length) / 2 + (dotOnOppositeSide ? -2 : 2),
                    width: 1.5,
                    height: length
                )
            case .vertical:
                separatorHighlightLayer.frame = CGRect(
                    x: (bounds.width - length) / 2 - 2,
                    y: 2,
                    width: length + 4,
                    height: max(bounds.height - 4, 8)
                )
                separatorLayer.frame = CGRect(
                    x: (bounds.width - length) / 2,
                    y: (bounds.height - 1.5) / 2,
                    width: length,
                    height: 1.5
                )
            }
        } else {
            let dotSize: CGFloat = 4.0
            let dotSpace = DockGeometry.runningDotSpace
            switch orientation {
            case .horizontal:
                let drawSize = min(bounds.width, max(bounds.height - dotSpace, 16))
                let iconY = dotOnOppositeSide ? (bounds.height - dotSpace - drawSize) : dotSpace
                let iconRect = CGRect(
                    x: (bounds.width - drawSize) / 2,
                    y: iconY,
                    width: drawSize,
                    height: drawSize
                )
                iconLayer.bounds = CGRect(origin: .zero, size: iconRect.size)
                iconLayer.position = CGPoint(x: iconRect.midX, y: iconRect.midY)

                let dotY = dotOnOppositeSide ? (bounds.height - dotSize - 0.5) : 0.5
                dotLayer.frame = CGRect(
                    x: (bounds.width - dotSize) / 2,
                    y: dotY,
                    width: dotSize,
                    height: dotSize
                )
            case .vertical:
                let drawSize = min(bounds.height, max(bounds.width - dotSpace, 16))
                let iconX = dotOnOppositeSide ? (bounds.width - dotSpace - drawSize) : dotSpace
                let iconRect = CGRect(
                    x: iconX,
                    y: (bounds.height - drawSize) / 2,
                    width: drawSize,
                    height: drawSize
                )
                iconLayer.bounds = CGRect(origin: .zero, size: iconRect.size)
                iconLayer.position = CGPoint(x: iconRect.midX, y: iconRect.midY)

                let dotX = dotOnOppositeSide ? (bounds.width - dotSize - 0.5) : 0.5
                dotLayer.frame = CGRect(
                    x: dotX,
                    y: (bounds.height - dotSize) / 2,
                    width: dotSize,
                    height: dotSize
                )
            }
        }

        CATransaction.commit()
    }

    // MARK: - Press Feedback

    private func setPressed(_ pressed: Bool) {
        guard isPressed != pressed else { return }
        isPressed = pressed

        let targetScale: CGFloat = pressed ? 0.90 : 1.0
        let transform = CATransform3DMakeScale(targetScale, targetScale, 1.0)
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = iconLayer.presentation()?.transform ?? iconLayer.transform
        spring.toValue = transform
        spring.damping = 20
        spring.stiffness = 400
        spring.duration = spring.settlingDuration

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        iconLayer.transform = transform
        let baseOpacity: Float = item.existsOnDisk ? 1.0 : 0.45
        iconLayer.opacity = pressed ? baseOpacity * 0.78 : baseOpacity
        CATransaction.commit()
        iconLayer.add(spring, forKey: "pressSpring")
    }

    // MARK: - Mouse / Click / Drag

    override func mouseDown(with event: NSEvent) {
        if isAutoDivider { return }

        if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.control) {
            delegate?.dockItemView(self, didRequestContextMenu: event)
            return
        }

        mouseDownLocation = event.locationInWindow
        isDraggingItem = false
        if item.kind != .separator {
            setPressed(true)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDraggableItem else { return }

        let current = event.locationInWindow
        let dist = hypot(current.x - mouseDownLocation.x, current.y - mouseDownLocation.y)
        if !isDraggingItem && dist >= 4 {
            isDraggingItem = true
            setPressed(false)
            setSeparatorHovered(false)
            delegate?.dockItemViewDidBeginDrag(self, event: event)
        }
        if isDraggingItem {
            delegate?.dockItemView(self, didDrag: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isAutoDivider { return }
        setPressed(false)

        if isDraggingItem {
            isDraggingItem = false
            delegate?.dockItemViewDidEndDrag(self, event: event)
            return
        }

        if item.kind != .separator {
            if item.kind == .app && !isRunning {
                playLaunchBounce()
            }
            delegate?.dockItemViewDidClick(self)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if isAutoDivider {
            super.rightMouseDown(with: event)
            return
        }
        delegate?.dockItemView(self, didRequestContextMenu: event)
    }
}
