import AppKit
import Foundation

@MainActor
protocol DockItemStripViewDelegate: AnyObject {
    func stripView(_ view: DockItemStripView, didClickItem item: DockItem)
    func stripView(_ view: DockItemStripView, contextMenuForItem item: DockItem, isTransientOpenApp: Bool) -> NSMenu
    func stripViewContextMenuForEmptyArea(_ view: DockItemStripView) -> NSMenu
    func stripViewDidClickEmptyState(_ view: DockItemStripView)
    func stripView(_ view: DockItemStripView, didHoverLabel text: String?, anchorRectInStrip: CGRect?)
    func stripView(_ view: DockItemStripView, didUpdateRemoveHint showRemove: Bool, anchorRectInStrip: CGRect?)
    func stripView(_ view: DockItemStripView, didUpdateGlassFrame pillFrame: CGRect)
    func stripView(_ view: DockItemStripView, didDropURLs urls: [URL], at index: Int)
    func stripView(_ view: DockItemStripView, didReorderItemFrom fromIndex: Int, to toIndex: Int)
    func stripView(_ view: DockItemStripView, didDragRemoveItem item: DockItem)
    func stripViewDidBeginWindowDrag(_ view: DockItemStripView, event: NSEvent)
    func stripView(_ view: DockItemStripView, didContinueWindowDrag event: NSEvent)
    func stripViewDidEndWindowDrag(_ view: DockItemStripView, event: NSEvent)
    func stripViewMouseDidEnter(_ view: DockItemStripView)
    func stripViewMouseDidExit(_ view: DockItemStripView)
}

@MainActor
final class DockItemStripView: NSView, DockItemViewDelegate {
    weak var delegate: DockItemStripViewDelegate?

    private var config: DockConfig
    private var openAppItems: [DockItem] = []
    private var pillInsets: DockEdgeInsets
    private var runningBundleIDs: Set<String> = []
    private var itemViews: [DockItemView] = []
    private(set) var currentGlassFrame: CGRect = .zero
    private(set) var isMoveMode: Bool = false

    private let moveHighlightLayer: CALayer = {
        let layer = CALayer()
        layer.borderWidth = 2.0
        layer.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.75).cgColor
        layer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        layer.isHidden = true
        return layer
    }()

    private let emptyHintStack: NSStackView = {
        let iconView = NSImageView()
        let symConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: "Add")?
            .withSymbolConfiguration(symConfig)
        iconView.contentTintColor = NSColor.secondaryLabelColor

        let label = NSTextField(labelWithString: "Drop apps here")
        label.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        label.textColor = NSColor.secondaryLabelColor

        let stack = NSStackView(views: [iconView, label])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        stack.isHidden = true
        return stack
    }()

    private let insertionIndicatorLayer: CALayer = {
        let layer = CALayer()
        layer.backgroundColor = NSColor.controlAccentColor.cgColor
        layer.cornerRadius = 1.5
        layer.shadowColor = NSColor.controlAccentColor.cgColor
        layer.shadowOpacity = 0.45
        layer.shadowRadius = 3
        layer.shadowOffset = .zero
        layer.isHidden = true
        return layer
    }()

    private var trackingArea: NSTrackingArea?
    private var isDraggingWindow = false

    // Smooth reorder drag state
    private var draggedItemIndex: Int?
    private var previewItemIndex: Int?
    private var dragGrabOffset: CGPoint = .zero
    private var draggedOffStrip = false
    private let dragRemovalThreshold: CGFloat = 40

    private var dropInsertionIndex: Int?

    // Wave magnification state (zero idle CPU — timer only runs during enter/exit blend)
    private var isPointerInPill = false
    private var pointerAlongAxis: CGFloat?
    private var magnificationBlend: CGFloat = 0
    private var targetMagnificationBlend: CGFloat = 0
    private var blendTimer: Timer?
    private var hoveredItemID: UUID?

    init(config: DockConfig, pillInsets: DockEdgeInsets) {
        self.config = config
        self.pillInsets = pillInsets
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.addSublayer(moveHighlightLayer)
        layer?.addSublayer(insertionIndicatorLayer)
        addSubview(emptyHintStack)
        registerForDraggedTypes([.fileURL])
        rebuildItemViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        blendTimer?.invalidate()
    }

    var allDisplayedItems: [DockItem] {
        if openAppItems.isEmpty {
            return config.items
        }
        if config.items.isEmpty {
            return openAppItems
        }
        return config.items + [DockItem.separator()] + openAppItems
    }

    private var pinnedItemCount: Int {
        config.items.count
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if isMoveMode {
            return currentGlassFrame.contains(local) ? self : nil
        }
        if currentGlassFrame.contains(local) {
            return super.hitTest(point)
        }
        for view in itemViews where view.frame.contains(local) {
            return super.hitTest(point)
        }
        return nil
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if isMoveMode {
            addCursorRect(currentGlassFrame, cursor: .openHand)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    func setMoveMode(_ enabled: Bool) {
        guard isMoveMode != enabled else { return }
        isMoveMode = enabled
        moveHighlightLayer.isHidden = !enabled
        if enabled {
            resetHoverAndMagnification()
        }
        window?.invalidateCursorRects(for: self)
        needsLayout = true
    }

    func update(
        config: DockConfig,
        openAppItems: [DockItem],
        pillInsets: DockEdgeInsets,
        runningBundleIDs: Set<String>
    ) {
        let pinnedChanged = self.config.items != config.items
        let openChanged = self.openAppItems.map(\.path) != openAppItems.map(\.path)
        self.config = config
        self.openAppItems = openAppItems
        self.pillInsets = pillInsets
        self.runningBundleIDs = runningBundleIDs

        if !config.magnificationEnabled {
            targetMagnificationBlend = 0
            magnificationBlend = 0
            stopBlendTimer()
        }

        let renderSize = maxRenderIconSize()
        let oppositeDot = isDotOnOppositeSide()

        if pinnedChanged || openChanged {
            rebuildItemViews()
        } else {
            for view in itemViews {
                let running = view.isTransientOpenApp || (view.item.bundleIdentifier.map { runningBundleIDs.contains($0) } ?? false)
                view.update(
                    orientation: config.effectiveOrientation,
                    baseIconSize: CGFloat(config.iconSize),
                    renderIconSize: renderSize,
                    isRunning: running,
                    dotOnOppositeSide: oppositeDot
                )
            }
        }

        emptyHintStack.isHidden = !itemViews.isEmpty
        needsLayout = true
    }

    func updateRunningApps(_ runningBundleIDs: Set<String>) {
        self.runningBundleIDs = runningBundleIDs
        for view in itemViews {
            let running = view.isTransientOpenApp || (view.item.bundleIdentifier.map { runningBundleIDs.contains($0) } ?? false)
            view.setRunning(running)
        }
    }

    func resetHoverAndMagnification() {
        if isPointerInPill {
            isPointerInPill = false
            delegate?.stripViewMouseDidExit(self)
        }
        clearHoverStates()
        setTargetMagnificationBlend(0)
    }

    func playRejectShake() {
        NSSound.beep()
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.duration = 0.25
        animation.values = [-6, 6, -4, 4, -2, 2, 0]
        layer?.add(animation, forKey: "shake")
    }

    private func clearHoverStates() {
        hoveredItemID = nil
        for view in itemViews where view.item.kind == .separator {
            view.setSeparatorHovered(false)
        }
        delegate?.stripView(self, didHoverLabel: nil, anchorRectInStrip: nil)
    }

    private func maxRenderIconSize() -> CGFloat {
        let base = CGFloat(config.iconSize)
        let peakScale = config.magnificationEnabled ? CGFloat(config.magnificationScale) : 1.12
        return ceil(base * peakScale)
    }

    private func isDotOnOppositeSide() -> Bool {
        switch config.effectiveOrientation {
        case .horizontal:
            return config.placement.snappedEdge == .top
        case .vertical:
            return config.placement.snappedEdge == .right
        }
    }

    private func rebuildItemViews() {
        for view in itemViews {
            view.removeFromSuperview()
        }
        itemViews.removeAll()

        let renderSize = maxRenderIconSize()
        let oppositeDot = isDotOnOppositeSide()

        // 1. Pinned items
        for item in config.items {
            let running = item.bundleIdentifier.map { runningBundleIDs.contains($0) } ?? false
            let view = DockItemView(
                item: item,
                orientation: config.effectiveOrientation,
                baseIconSize: CGFloat(config.iconSize),
                renderIconSize: renderSize,
                isRunning: running,
                dotOnOppositeSide: oppositeDot,
                isTransientOpenApp: false,
                isAutoDivider: false
            )
            view.delegate = self
            addSubview(view)
            itemViews.append(view)
        }

        // 2. Automatic subtle divider + transient open apps (when enabled for this dock)
        if !openAppItems.isEmpty {
            if !config.items.isEmpty {
                let dividerView = DockItemView(
                    item: DockItem.separator(),
                    orientation: config.effectiveOrientation,
                    baseIconSize: CGFloat(config.iconSize),
                    renderIconSize: renderSize,
                    isRunning: false,
                    dotOnOppositeSide: oppositeDot,
                    isTransientOpenApp: false,
                    isAutoDivider: true
                )
                addSubview(dividerView)
                itemViews.append(dividerView)
            }

            for openItem in openAppItems {
                let view = DockItemView(
                    item: openItem,
                    orientation: config.effectiveOrientation,
                    baseIconSize: CGFloat(config.iconSize),
                    renderIconSize: renderSize,
                    isRunning: true,
                    dotOnOppositeSide: oppositeDot,
                    isTransientOpenApp: true,
                    isAutoDivider: false
                )
                view.delegate = self
                addSubview(view)
                itemViews.append(view)
            }
        }

        emptyHintStack.isHidden = !itemViews.isEmpty
        needsLayout = true
    }

    // MARK: - Resting Pill Frame & Layout

    private var restingPillRect: CGRect {
        CGRect(
            x: pillInsets.left,
            y: pillInsets.bottom,
            width: max(bounds.width - pillInsets.left - pillInsets.right, 1),
            height: max(bounds.height - pillInsets.top - pillInsets.bottom, 1)
        )
    }

    override func layout() {
        super.layout()
        layoutContent(animated: false)
    }

    /// Computes target slot frames for all views (accounting for live drag-reorder preview and magnification).
    private func computeSlotLayout() -> (pillFrame: CGRect, orderedViews: [DockItemView], frames: [CGRect]) {
        let orientation = config.effectiveOrientation
        let baseIconSize = CGFloat(config.iconSize)
        let spacing = DockGeometry.itemSpacing
        let dotSpace = DockGeometry.runningDotSpace
        let paddingAlong = DockGeometry.paddingAlongAxis
        let paddingCross = DockGeometry.paddingCrossAxis
        let restingPill = restingPillRect

        var orderedViews = itemViews
        if let from = draggedItemIndex, let to = previewItemIndex,
           from != to, from < pinnedItemCount, to < pinnedItemCount,
           from < orderedViews.count, to < orderedViews.count {
            let moved = orderedViews.remove(at: from)
            orderedViews.insert(moved, at: to)
        }

        let restingSizes: [CGFloat] = orderedViews.map {
            $0.item.kind == .separator ? DockGeometry.separatorThickness : baseIconSize
        }
        let restingContentLength = restingSizes.reduce(0, +) + spacing * CGFloat(max(orderedViews.count - 1, 0))

        let restingStart: CGFloat = orientation == .horizontal
            ? (restingPill.midX - restingContentLength / 2)
            : (restingPill.midY + restingContentLength / 2)

        var restingCenters: [CGFloat] = []
        restingCenters.reserveCapacity(orderedViews.count)
        var scan = restingStart
        for size in restingSizes {
            if orientation == .horizontal {
                restingCenters.append(scan + size / 2)
                scan += size + spacing
            } else {
                restingCenters.append(scan - size / 2)
                scan -= (size + spacing)
            }
        }

        let peakScale: CGFloat = config.magnificationEnabled ? CGFloat(config.magnificationScale) : 1.08
        let effectiveBlend = (draggedItemIndex == nil && !isMoveMode) ? magnificationBlend : 0
        let radius = baseIconSize * (config.magnificationEnabled ? 2.25 : 0.75)

        var magnifiedSizes: [CGFloat] = []
        magnifiedSizes.reserveCapacity(orderedViews.count)
        for (idx, view) in orderedViews.enumerated() {
            if view.item.kind == .separator {
                magnifiedSizes.append(DockGeometry.separatorThickness)
                continue
            }
            if effectiveBlend > 0.001, let pointer = pointerAlongAxis {
                let dist = abs(pointer - restingCenters[idx])
                if dist < radius {
                    let wave = 0.5 * (1.0 + cos(.pi * dist / radius))
                    let scale = 1.0 + (peakScale - 1.0) * wave * effectiveBlend
                    magnifiedSizes.append(baseIconSize * scale)
                } else {
                    magnifiedSizes.append(baseIconSize)
                }
            } else {
                magnifiedSizes.append(baseIconSize)
            }
        }

        let totalLength = magnifiedSizes.reduce(0, +) + spacing * CGFloat(max(orderedViews.count - 1, 0))
        let expandedPillFrame: CGRect
        switch orientation {
        case .horizontal:
            let pillWidth = min(max(totalLength + paddingAlong * 2, restingPill.height), bounds.width)
            expandedPillFrame = CGRect(
                x: restingPill.midX - pillWidth / 2,
                y: restingPill.origin.y,
                width: pillWidth,
                height: restingPill.height
            )
        case .vertical:
            let pillHeight = min(max(totalLength + paddingAlong * 2, restingPill.width), bounds.height)
            expandedPillFrame = CGRect(
                x: restingPill.origin.x,
                y: restingPill.midY - pillHeight / 2,
                width: restingPill.width,
                height: pillHeight
            )
        }

        let oppositeDot = isDotOnOppositeSide()
        var frames: [CGRect] = []
        frames.reserveCapacity(orderedViews.count)

        switch orientation {
        case .horizontal:
            var cursorX = expandedPillFrame.midX - totalLength / 2
            for (idx, view) in orderedViews.enumerated() {
                let width = magnifiedSizes[idx]
                let isSep = view.item.kind == .separator
                let itemHeight = (isSep ? baseIconSize : width) + dotSpace
                let y = oppositeDot
                    ? (expandedPillFrame.maxY - paddingCross - itemHeight)
                    : (expandedPillFrame.minY + paddingCross)
                frames.append(CGRect(x: cursorX, y: y, width: width, height: itemHeight))
                cursorX += width + spacing
            }
        case .vertical:
            var cursorY = expandedPillFrame.midY + totalLength / 2
            for (idx, view) in orderedViews.enumerated() {
                let height = magnifiedSizes[idx]
                let isSep = view.item.kind == .separator
                let itemWidth = (isSep ? baseIconSize : height) + dotSpace
                let x = oppositeDot
                    ? (expandedPillFrame.maxX - paddingCross - itemWidth)
                    : (expandedPillFrame.minX + paddingCross)
                cursorY -= height
                frames.append(CGRect(x: x, y: cursorY, width: itemWidth, height: height))
                cursorY -= spacing
            }
        }

        return (expandedPillFrame, orderedViews, frames)
    }

    private func layoutContent(animated: Bool) {
        let orientation = config.effectiveOrientation
        let restingPill = restingPillRect

        if itemViews.isEmpty {
            currentGlassFrame = restingPill
            updateMoveHighlightFrame(for: restingPill)
            delegate?.stripView(self, didUpdateGlassFrame: restingPill)
            emptyHintStack.orientation = orientation == .horizontal ? .horizontal : .vertical
            let fitting = emptyHintStack.fittingSize
            emptyHintStack.frame = CGRect(
                x: restingPill.midX - fitting.width / 2,
                y: restingPill.midY - fitting.height / 2,
                width: fitting.width,
                height: fitting.height
            )
            return
        }

        let (expandedPillFrame, orderedViews, frames) = computeSlotLayout()
        currentGlassFrame = expandedPillFrame
        updateMoveHighlightFrame(for: expandedPillFrame)
        delegate?.stripView(self, didUpdateGlassFrame: expandedPillFrame)

        let draggedView: DockItemView? = draggedItemIndex.flatMap { $0 < itemViews.count ? itemViews[$0] : nil }

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.2, 1.0)
                ctx.allowsImplicitAnimation = true
                for (view, frame) in zip(orderedViews, frames) {
                    if view === draggedView { continue }
                    view.animator().frame = frame
                }
            }
        } else {
            for (view, frame) in zip(orderedViews, frames) {
                if view === draggedView { continue }
                view.frame = frame
            }
        }

        updateHoveredTooltipFromCurrentPointer()
    }

    private func updateMoveHighlightFrame(for pillFrame: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        moveHighlightLayer.frame = pillFrame
        moveHighlightLayer.cornerRadius = DockGeometry.cornerRadius(for: pillFrame.size)
        CATransaction.commit()
    }

    // MARK: - Smooth Enter/Exit Magnification Blend

    private func setTargetMagnificationBlend(_ target: CGFloat) {
        targetMagnificationBlend = target
        guard abs(magnificationBlend - target) > 0.002 else {
            magnificationBlend = target
            stopBlendTimer()
            layoutContent(animated: false)
            return
        }
        guard blendTimer == nil else { return }
        blendTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stepMagnificationBlend()
            }
        }
    }

    private func stepMagnificationBlend() {
        let diff = targetMagnificationBlend - magnificationBlend
        if abs(diff) < 0.006 {
            magnificationBlend = targetMagnificationBlend
            stopBlendTimer()
            if magnificationBlend == 0 {
                pointerAlongAxis = nil
            }
            layoutContent(animated: false)
            return
        }
        magnificationBlend += diff * 0.24
        layoutContent(animated: false)
    }

    private func stopBlendTimer() {
        blendTimer?.invalidate()
        blendTimer = nil
    }

    // MARK: - Mouse / Magnification / Dedicated Move Mode Drag

    private func isPointInsideInteractiveDock(_ localPoint: NSPoint) -> Bool {
        if currentGlassFrame.insetBy(dx: -4, dy: -4).contains(localPoint) {
            return true
        }
        return itemViews.contains { $0.frame.contains(localPoint) }
    }

    override func mouseMoved(with event: NSEvent) {
        guard !isMoveMode else { return }

        let local = convert(event.locationInWindow, from: nil)
        let inside = isPointInsideInteractiveDock(local)

        if inside {
            if !isPointerInPill {
                isPointerInPill = true
                delegate?.stripViewMouseDidEnter(self)
            }
            pointerAlongAxis = config.effectiveOrientation == .horizontal ? local.x : local.y
            setTargetMagnificationBlend(1.0)
            layoutContent(animated: false)
        } else if isPointerInPill {
            isPointerInPill = false
            clearHoverStates()
            delegate?.stripViewMouseDidExit(self)
            setTargetMagnificationBlend(0.0)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        resetHoverAndMagnification()
    }

    private func updateHoveredTooltipFromCurrentPointer() {
        guard isPointerInPill, !isMoveMode, draggedItemIndex == nil, !isDraggingWindow, let window else {
            if hoveredItemID != nil {
                clearHoverStates()
            }
            return
        }

        let mouseInWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let local = convert(mouseInWindow, from: nil)

        var matchedView: DockItemView?
        for view in itemViews {
            let isHit = !view.isAutoDivider && view.frame.contains(local)
            if view.item.kind == .separator && !view.isAutoDivider {
                view.setSeparatorHovered(isHit)
            }
            if isHit {
                matchedView = view
            }
        }

        if let hovered = matchedView {
            hoveredItemID = hovered.item.id
            let text: String
            if hovered.item.kind == .separator {
                text = "Separator"
            } else {
                text = hovered.item.existsOnDisk ? hovered.item.displayName : "Not found: \(hovered.item.displayName)"
            }
            delegate?.stripView(self, didHoverLabel: text, anchorRectInStrip: hovered.frame)
        } else if hoveredItemID != nil {
            hoveredItemID = nil
            delegate?.stripView(self, didHoverLabel: nil, anchorRectInStrip: nil)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if isMoveMode {
            isDraggingWindow = true
            delegate?.stripViewDidBeginWindowDrag(self, event: event)
            return
        }

        if event.modifierFlags.contains(.control) {
            showEmptyAreaContextMenu(with: event)
            return
        }

        if itemViews.isEmpty {
            delegate?.stripViewDidClickEmptyState(self)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if isDraggingWindow && isMoveMode {
            delegate?.stripView(self, didContinueWindowDrag: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isDraggingWindow {
            isDraggingWindow = false
            delegate?.stripViewDidEndWindowDrag(self, event: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        showEmptyAreaContextMenu(with: event)
    }

    private func showEmptyAreaContextMenu(with event: NSEvent) {
        resetHoverAndMagnification()
        guard let menu = delegate?.stripViewContextMenuForEmptyArea(self) else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    // MARK: - DockItemViewDelegate (Silky-Smooth Reorder & Remove)

    func dockItemViewDidClick(_ view: DockItemView) {
        delegate?.stripView(self, didClickItem: view.item)
    }

    func dockItemView(_ view: DockItemView, didRequestContextMenu event: NSEvent) {
        clearHoverStates()
        guard let menu = delegate?.stripView(self, contextMenuForItem: view.item, isTransientOpenApp: view.isTransientOpenApp) else {
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    func dockItemViewDidBeginDrag(_ view: DockItemView, event: NSEvent) {
        guard !isMoveMode,
              let index = itemViews.firstIndex(of: view),
              index < pinnedItemCount else { return }

        clearHoverStates()
        stopBlendTimer()
        magnificationBlend = 0
        targetMagnificationBlend = 0
        pointerAlongAxis = nil

        // Settle resting frames cleanly before starting live cursor-follow drag
        layoutContent(animated: false)

        let local = convert(event.locationInWindow, from: nil)
        dragGrabOffset = CGPoint(x: local.x - view.frame.origin.x, y: local.y - view.frame.origin.y)
        draggedItemIndex = index
        previewItemIndex = index
        draggedOffStrip = false

        // Elevate dragged view above all siblings
        addSubview(view, positioned: .above, relativeTo: nil)
        view.setDragLifted(true)
        view.alphaValue = 0.92
    }

    func dockItemView(_ view: DockItemView, didDrag event: NSEvent) {
        guard draggedItemIndex != nil else { return }
        let localPoint = convert(event.locationInWindow, from: nil)

        // Move dragged view 1:1 with the cursor so it feels completely fluid
        view.frame.origin = CGPoint(
            x: localPoint.x - dragGrabOffset.x,
            y: localPoint.y - dragGrabOffset.y
        )

        let pill = restingPillRect
        let perpendicularDistance: CGFloat
        switch config.effectiveOrientation {
        case .horizontal:
            if localPoint.y < pill.minY {
                perpendicularDistance = pill.minY - localPoint.y
            } else if localPoint.y > pill.maxY {
                perpendicularDistance = localPoint.y - pill.maxY
            } else {
                perpendicularDistance = 0
            }
        case .vertical:
            if localPoint.x < pill.minX {
                perpendicularDistance = pill.minX - localPoint.x
            } else if localPoint.x > pill.maxX {
                perpendicularDistance = localPoint.x - pill.maxX
            } else {
                perpendicularDistance = 0
            }
        }

        let nowOffStrip = perpendicularDistance > dragRemovalThreshold
        if nowOffStrip != draggedOffStrip {
            draggedOffStrip = nowOffStrip
            delegate?.stripView(self, didUpdateRemoveHint: draggedOffStrip, anchorRectInStrip: view.frame)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                view.animator().alphaValue = nowOffStrip ? 0.35 : 0.92
            }
        } else if draggedOffStrip {
            delegate?.stripView(self, didUpdateRemoveHint: true, anchorRectInStrip: view.frame)
        }

        if !draggedOffStrip {
            let centerPoint = CGPoint(x: view.frame.midX, y: view.frame.midY)
            let targetIdx = pinnedInsertionIndex(for: centerPoint, clampingToPinned: true)
            if targetIdx != previewItemIndex {
                previewItemIndex = targetIdx
                layoutContent(animated: true)
            }
        }
    }

    func dockItemViewDidEndDrag(_ view: DockItemView, event: NSEvent) {
        let fromIndex = draggedItemIndex
        let toIndex = previewItemIndex
        let shouldRemove = draggedOffStrip

        delegate?.stripView(self, didUpdateRemoveHint: false, anchorRectInStrip: nil)
        view.setDragLifted(false)

        if shouldRemove {
            draggedItemIndex = nil
            previewItemIndex = nil
            draggedOffStrip = false
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.16
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                view.animator().alphaValue = 0.0
            }, completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.delegate?.stripView(self, didDragRemoveItem: view.item)
                }
            })
            return
        }

        // Compute exact resting target slot and smoothly glide the dragged view into it before committing
        let (_, orderedViews, frames) = computeSlotLayout()
        let targetFrame = orderedViews.firstIndex(of: view).map { frames[$0] } ?? view.frame

        draggedItemIndex = nil
        previewItemIndex = nil
        draggedOffStrip = false

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.2, 1.0)
            ctx.allowsImplicitAnimation = true
            view.animator().frame = targetFrame
            view.animator().alphaValue = 1.0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let from = fromIndex, let to = toIndex, from != to {
                    self.delegate?.stripView(self, didReorderItemFrom: from, to: to)
                } else {
                    self.layoutContent(animated: false)
                }
            }
        })
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isMoveMode, canAccept(draggingInfo: sender) else { return [] }
        delegate?.stripViewMouseDidEnter(self)
        updateDropIndicator(for: sender)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isMoveMode, canAccept(draggingInfo: sender) else { return [] }
        updateDropIndicator(for: sender)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        hideDropIndicator()
        delegate?.stripViewMouseDidExit(self)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { hideDropIndicator() }
        let urls = extractFileURLs(from: sender)
        guard !urls.isEmpty else { return false }
        let index = dropInsertionIndex ?? pinnedItemCount
        delegate?.stripView(self, didDropURLs: urls, at: index)
        return true
    }

    private func canAccept(draggingInfo: NSDraggingInfo) -> Bool {
        !extractFileURLs(from: draggingInfo).isEmpty
    }

    private func extractFileURLs(from draggingInfo: NSDraggingInfo) -> [URL] {
        let pasteboard = draggingInfo.draggingPasteboard
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] else {
            return []
        }
        return urls
    }

    private func updateDropIndicator(for draggingInfo: NSDraggingInfo) {
        let point = convert(draggingInfo.draggingLocation, from: nil)
        let index = pinnedInsertionIndex(for: point, clampingToPinned: false)
        dropInsertionIndex = index

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        insertionIndicatorLayer.isHidden = false

        let orientation = config.effectiveOrientation
        let iconSize = CGFloat(config.iconSize)
        let pill = currentGlassFrame
        let pinnedViews = Array(itemViews.prefix(pinnedItemCount))

        switch orientation {
        case .horizontal:
            let x: CGFloat
            if pinnedViews.isEmpty {
                x = pill.midX - 1.5
            } else if index >= pinnedViews.count {
                x = pinnedViews[pinnedViews.count - 1].frame.maxX + 2.5
            } else {
                x = pinnedViews[index].frame.minX - 5.5
            }
            insertionIndicatorLayer.frame = CGRect(
                x: x,
                y: pill.minY + DockGeometry.paddingCrossAxis + DockGeometry.runningDotSpace,
                width: 3,
                height: iconSize
            )
        case .vertical:
            let y: CGFloat
            if pinnedViews.isEmpty {
                y = pill.midY - 1.5
            } else if index >= pinnedViews.count {
                y = pinnedViews[pinnedViews.count - 1].frame.minY - 5.5
            } else {
                y = pinnedViews[index].frame.maxY + 2.5
            }
            insertionIndicatorLayer.frame = CGRect(
                x: pill.minX + DockGeometry.paddingCrossAxis + DockGeometry.runningDotSpace,
                y: y,
                width: iconSize,
                height: 3
            )
        }
        CATransaction.commit()
    }

    private func hideDropIndicator() {
        dropInsertionIndex = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        insertionIndicatorLayer.isHidden = true
        CATransaction.commit()
    }

    private func pinnedInsertionIndex(for localPoint: NSPoint, clampingToPinned: Bool) -> Int {
        guard pinnedItemCount > 0 else { return 0 }
        let orientation = config.effectiveOrientation
        let (_, orderedViews, frames) = computeSlotLayout()
        let count = min(pinnedItemCount, orderedViews.count)

        for index in 0..<count {
            let slotFrame = frames[index]
            switch orientation {
            case .horizontal:
                if localPoint.x < slotFrame.midX {
                    return index
                }
            case .vertical:
                if localPoint.y > slotFrame.midY {
                    return index
                }
            }
        }
        return clampingToPinned ? max(count - 1, 0) : count
    }
}
