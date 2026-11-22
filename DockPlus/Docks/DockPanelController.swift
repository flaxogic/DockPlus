import AppKit
import Foundation

final class DockPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Transparent root container so NSGlassEffectView is never assigned directly as window.contentView
/// and clicks outside the glass pill / magnified icons pass straight through to windows underneath.
private final class DockRootView: NSView {
    weak var interactiveStripView: DockItemStripView?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let strip = interactiveStripView else { return nil }
        return strip.hitTest(convert(point, to: strip))
    }
}

@MainActor
protocol DockPanelControllerDelegate: AnyObject {
    func panelController(_ controller: DockPanelController, didUpdatePlacement placement: DockConfig.Placement, orientation: DockConfig.Orientation)
    func panelController(_ controller: DockPanelController, didDropURLs urls: [URL], at index: Int) -> Bool
    func panelController(_ controller: DockPanelController, didReorderItemFrom fromIndex: Int, to toIndex: Int)
    func panelController(_ controller: DockPanelController, didRemoveItem item: DockItem)
    func panelController(_ controller: DockPanelController, didPinOpenApp item: DockItem)
    func panelController(_ controller: DockPanelController, isOpenAtLogin item: DockItem) -> Bool
    func panelController(_ controller: DockPanelController, didToggleOpenAtLogin item: DockItem)
    func panelController(_ controller: DockPanelController, otherDocksFor dockID: UUID) -> [DockConfig]
    func panelController(_ controller: DockPanelController, didMoveItem item: DockItem, isTransientOpenApp: Bool, toDock targetDockID: UUID)
    func panelController(_ controller: DockPanelController, didCopyItem item: DockItem, toDock targetDockID: UUID)
    func panelController(_ controller: DockPanelController, didRequestSnapToEdge edge: DockConfig.Edge?)
    func panelController(_ controller: DockPanelController, didSetMoveMode enabled: Bool)
    func panelControllerDidRequestToggleMagnification(_ controller: DockPanelController)
    func panelControllerDidRequestAddItems(_ controller: DockPanelController)
    func panelControllerDidRequestAddSeparator(_ controller: DockPanelController)
    func panelControllerDidRequestToggleAutoHide(_ controller: DockPanelController)
    func panelControllerDidRequestToggleOrientation(_ controller: DockPanelController)
    func panelControllerDidRequestNewDock(_ controller: DockPanelController)
    func panelControllerDidRequestDeleteDock(_ controller: DockPanelController)
    func panelControllerDidRequestManageDocks(_ controller: DockPanelController)
}

@MainActor
final class DockPanelController: DockItemStripViewDelegate {
    let dockID: UUID
    private(set) var config: DockConfig
    private(set) var openAppItems: [DockItem] = []
    private(set) var isMoveMode: Bool = false
    weak var delegate: DockPanelControllerDelegate?

    let panel: DockPanel
    private let rootView: DockRootView
    private let stageView: NSView
    private let glassBackgroundView: LiquidGlassView
    private let stripView: DockItemStripView
    private let tooltipWindow = DockTooltipWindow()
    private let moveBannerWindow = DockMoveBannerWindow()
    private let edgeTriggerWindow = DockEdgeTriggerWindow()
    private let displayObserver: DisplayObserver
    private var autoHideController: AutoHideController!

    private var currentPillInsets: DockEdgeInsets
    private var runningBundleIDs: Set<String> = []
    private var isGloballyHidden = false
    private var isLogicallyShown = false
    private var visibilityGeneration: Int = 0
    private var lastPresentedDisplayUUID: String?

    private var dragStartMouseLocation: NSPoint = .zero
    private var dragStartPanelOrigin: NSPoint = .zero
    private var isDraggingPanel = false

    init(
        config: DockConfig,
        openAppItems: [DockItem],
        displayObserver: DisplayObserver,
        runningBundleIDs: Set<String>
    ) {
        self.dockID = config.id
        self.config = config
        self.openAppItems = openAppItems
        self.displayObserver = displayObserver
        self.runningBundleIDs = runningBundleIDs

        let displayed = Self.combinedDisplayedItems(pinned: config.items, openApps: openAppItems)
        let initialPillSize = DockGeometry.panelSize(for: config, displayedItems: displayed)
        let initialInsets = DockGeometry.magnificationHeadroom(for: config, displayedItemCount: displayed.count)
        self.currentPillInsets = initialInsets

        let initialWindowRect = NSRect(
            x: 0,
            y: 0,
            width: initialPillSize.width + initialInsets.left + initialInsets.right,
            height: initialPillSize.height + initialInsets.top + initialInsets.bottom
        )
        let initialPillRect = NSRect(
            x: initialInsets.left,
            y: initialInsets.bottom,
            width: initialPillSize.width,
            height: initialPillSize.height
        )
        let cornerRadius = DockGeometry.cornerRadius(for: initialPillSize)

        let panel = DockPanel(
            contentRect: initialWindowRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovable = false
        panel.ignoresMouseEvents = false
        panel.animationBehavior = .none

        let root = DockRootView(frame: initialWindowRect)
        root.autoresizingMask = [.width, .height]
        root.layerUsesCoreImageFilters = false

        let stage = NSView(frame: initialWindowRect)
        stage.layerUsesCoreImageFilters = false

        panel.hasShadow = false
        panel.alphaValue = 0.0
        let glassBg = LiquidGlassView(
            frame: initialPillRect,
            cornerRadius: cornerRadius,
            variant: .dockPill,
            transparency: config.glassTransparency,
            tintColor: config.tintColor
        )

        let strip = DockItemStripView(config: config, pillInsets: initialInsets)
        strip.frame = initialWindowRect
        strip.autoresizingMask = [.width, .height]

        stage.addSubview(glassBg)
        stage.addSubview(strip)
        root.addSubview(stage)
        root.interactiveStripView = strip
        panel.contentView = root

        self.panel = panel
        self.rootView = root
        self.stageView = stage
        self.glassBackgroundView = glassBg
        self.stripView = strip

        self.autoHideController = AutoHideController { [weak self] _ in
            self?.tooltipWindow.hide()
            self?.refreshVisibilityAndPosition(animated: true)
        }

        self.moveBannerWindow.onDone = { [weak self] in
            guard let self else { return }
            self.delegate?.panelController(self, didSetMoveMode: false)
        }

        self.edgeTriggerWindow.onMouseEntered = { [weak self] in
            self?.autoHideController.mouseEntered()
        }
        self.edgeTriggerWindow.onMouseExited = { [weak self] in
            self?.autoHideController.edgeTriggerMouseExited()
        }

        strip.delegate = self
        strip.update(config: config, openAppItems: openAppItems, pillInsets: initialInsets, runningBundleIDs: runningBundleIDs)
        tooltipWindow.setGlassAppearance(transparency: config.glassTransparency, tintColor: config.tintColor)
        moveBannerWindow.setGlassAppearance(transparency: config.glassTransparency, tintColor: config.tintColor)
        autoHideController.setEnabled(config.effectiveAutoHide, startHidden: config.effectiveAutoHide)
        refreshVisibilityAndPosition(animated: true)
    }

    private static func combinedDisplayedItems(pinned: [DockItem], openApps: [DockItem]) -> [DockItem] {
        if openApps.isEmpty { return pinned }
        if pinned.isEmpty { return openApps }
        return pinned + [DockItem.separator()] + openApps
    }

    func close() {
        autoHideController.cancelPending()
        tooltipWindow.close()
        moveBannerWindow.close()
        edgeTriggerWindow.close()
        panel.orderOut(nil)
        panel.close()
    }

    func setMoveMode(_ enabled: Bool) {
        guard isMoveMode != enabled else { return }
        isMoveMode = enabled
        stripView.setMoveMode(enabled)
        tooltipWindow.hide()
        if enabled {
            autoHideController.revealImmediately()
            refreshVisibilityAndPosition(animated: true)
            updateMoveBannerPosition()
        } else {
            moveBannerWindow.hide()
            scheduleAutoHideIfCursorOutside()
        }
    }

    func update(config: DockConfig, openAppItems: [DockItem]) {
        let oldConfig = self.config
        let oldOpenCount = self.openAppItems.count
        let autoHideChanged = oldConfig.effectiveAutoHide != config.effectiveAutoHide
        let visibilityChanged = oldConfig.isVisible != config.isVisible
        let shouldAnimate =
            visibilityChanged ||
            oldConfig.items.count != config.items.count ||
            oldOpenCount != openAppItems.count ||
            oldConfig.orientation != config.orientation ||
            oldConfig.placement != config.placement

        self.config = config
        self.openAppItems = openAppItems

        glassBackgroundView.transparency = config.glassTransparency
        glassBackgroundView.tintColor = config.tintColor
        tooltipWindow.setGlassAppearance(transparency: config.glassTransparency, tintColor: config.tintColor)
        moveBannerWindow.setGlassAppearance(transparency: config.glassTransparency, tintColor: config.tintColor)

        if autoHideChanged {
            autoHideController.setEnabled(config.effectiveAutoHide, startHidden: false)
        }
        refreshVisibilityAndPosition(animated: shouldAnimate)
        if autoHideChanged && config.effectiveAutoHide {
            scheduleAutoHideIfCursorOutside()
        }
        if isMoveMode {
            updateMoveBannerPosition()
        }
    }

    func updateRunningApps(_ bundleIDs: Set<String>) {
        self.runningBundleIDs = bundleIDs
        stripView.updateRunningApps(bundleIDs)
    }

    func updateGlobalHidden(_ hidden: Bool) {
        guard isGloballyHidden != hidden else { return }
        isGloballyHidden = hidden
        if hidden {
            tooltipWindow.hide()
            moveBannerWindow.hide()
            stripView.resetHoverAndMagnification()
        }
        refreshVisibilityAndPosition(animated: true)
    }

    func handleDisplaysChanged() {
        tooltipWindow.hide()
        refreshVisibilityAndPosition(animated: true)
        if isMoveMode {
            updateMoveBannerPosition()
        }
    }

    func resolvedDisplay() -> DisplayInfo? {
        if let displayUUID = config.placement.displayUUID {
            return displayObserver.display(forUUID: displayUUID)
        }
        if case .floating(let x, let y, nil) = config.placement {
            return displayObserver.display(containing: CGPoint(x: x, y: y)) ?? displayObserver.mainDisplay()
        }
        return displayObserver.mainDisplay()
    }

    func refreshVisibilityAndPosition(animated: Bool) {
        guard !isDraggingPanel else { return }

        guard let display = resolvedDisplay() else {
            // Monitor was disconnected: tear down immediately so nothing lingers off-display.
            visibilityGeneration += 1
            isLogicallyShown = false
            lastPresentedDisplayUUID = nil
            tooltipWindow.hide()
            moveBannerWindow.hide()
            edgeTriggerWindow.hide()
            panel.orderOut(nil)
            panel.alphaValue = 0
            return
        }

        let displayed = Self.combinedDisplayedItems(pinned: config.items, openApps: openAppItems)
        let pillSize = DockGeometry.panelSize(for: config, displayedItems: displayed)
        let desiredInsets = DockGeometry.magnificationHeadroom(for: config, displayedItemCount: displayed.count)
        let visiblePillFrame = DockGeometry.visibleFrame(
            for: config.placement,
            panelSize: pillSize,
            in: display.visibleFrame
        )
        let (clippedWindowFrame, clippedInsets) = DockGeometry.clippedWindowLayout(
            forPillFrame: visiblePillFrame,
            desiredInsets: desiredInsets,
            within: display.frame
        )

        currentPillInsets = clippedInsets
        stripView.update(config: config, openAppItems: openAppItems, pillInsets: clippedInsets, runningBundleIDs: runningBundleIDs)
        updateCornerRadius(for: pillSize)

        let isHiddenByUser = !config.isVisible || isGloballyHidden
        let isAutoHidden = !isMoveMode && config.effectiveAutoHide && autoHideController.isHidden
        let shouldBeShown = !isHiddenByUser && !isAutoHidden

        if !shouldBeShown {
            if !isHiddenByUser, isAutoHidden, let edge = config.placement.snappedEdge {
                edgeTriggerWindow.show(
                    for: edge,
                    visibleDockFrame: visiblePillFrame,
                    visibleFrame: display.visibleFrame,
                    screenFrame: display.frame
                )
            } else {
                edgeTriggerWindow.hide()
            }

            animateRetreat(
                edge: config.placement.snappedEdge,
                pillSize: pillSize,
                insets: clippedInsets,
                windowFrame: clippedWindowFrame
            )
            return
        }

        edgeTriggerWindow.hide()

        let switchedDisplay = (lastPresentedDisplayUUID != nil && lastPresentedDisplayUUID != display.uuid)
        if !isLogicallyShown || switchedDisplay || !panel.isVisible {
            animateAppear(
                windowFrame: clippedWindowFrame,
                pillSize: pillSize,
                insets: clippedInsets,
                edge: config.placement.snappedEdge,
                displayUUID: display.uuid,
                forceStartFromRetreated: switchedDisplay || !panel.isVisible
            )
        } else {
            // Already visible on this display — update size/position cleanly
            if animated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.20
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    panel.animator().setFrame(clippedWindowFrame, display: true)
                    stageView.animator().frame = CGRect(origin: .zero, size: clippedWindowFrame.size)
                    panel.animator().alphaValue = 1.0
                }
            } else {
                panel.setFrame(clippedWindowFrame, display: true)
                stageView.frame = CGRect(origin: .zero, size: clippedWindowFrame.size)
                panel.alphaValue = 1.0
            }
            stripView.needsLayout = true
            if isMoveMode {
                updateMoveBannerPosition()
            }
        }
    }

    private func animateAppear(
        windowFrame: CGRect,
        pillSize: CGSize,
        insets: DockEdgeInsets,
        edge: DockConfig.Edge?,
        displayUUID: String,
        forceStartFromRetreated: Bool
    ) {
        visibilityGeneration += 1
        let gen = visibilityGeneration
        isLogicallyShown = true
        lastPresentedDisplayUUID = displayUUID

        let pillFrameInWindow = CGRect(
            x: insets.left,
            y: insets.bottom,
            width: pillSize.width,
            height: pillSize.height
        )
        let retreatedOrigin = DockGeometry.retreatedStageOffset(
            for: edge,
            pillFrameInWindow: pillFrameInWindow,
            windowSize: windowFrame.size
        )

        panel.setFrame(windowFrame, display: false)
        if forceStartFromRetreated || !panel.isVisible || panel.alphaValue < 0.02 {
            stageView.frame = CGRect(origin: retreatedOrigin, size: windowFrame.size)
            panel.alphaValue = 0.0
            stripView.needsLayout = true
            stripView.layoutSubtreeIfNeeded()
            panel.orderFrontRegardless()
        } else {
            stripView.needsLayout = true
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            ctx.allowsImplicitAnimation = true
            stageView.animator().frame = CGRect(origin: .zero, size: windowFrame.size)
            panel.animator().alphaValue = 1.0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.visibilityGeneration == gen, self.isLogicallyShown else { return }
                if self.isMoveMode {
                    self.updateMoveBannerPosition()
                }
            }
        })
    }

    private func animateRetreat(
        edge: DockConfig.Edge?,
        pillSize: CGSize,
        insets: DockEdgeInsets,
        windowFrame: CGRect
    ) {
        visibilityGeneration += 1
        let gen = visibilityGeneration
        let wasShown = isLogicallyShown || (panel.isVisible && panel.alphaValue > 0.02)
        isLogicallyShown = false

        tooltipWindow.hide()
        moveBannerWindow.hide()
        stripView.resetHoverAndMagnification()

        guard wasShown, panel.isVisible else {
            panel.alphaValue = 0.0
            panel.orderOut(nil)
            return
        }

        let currentSize = panel.frame.size
        let pillFrameInWindow = CGRect(
            x: insets.left,
            y: insets.bottom,
            width: pillSize.width,
            height: pillSize.height
        )
        let retreatedOrigin = DockGeometry.retreatedStageOffset(
            for: edge,
            pillFrameInWindow: pillFrameInWindow,
            windowSize: currentSize
        )

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.21
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 1.0, 1.0)
            ctx.allowsImplicitAnimation = true
            stageView.animator().setFrameOrigin(retreatedOrigin)
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.visibilityGeneration == gen, !self.isLogicallyShown else { return }
                self.panel.orderOut(nil)
                // Keep window frame synced for the next appear
                self.panel.setFrame(windowFrame, display: false)
                self.stageView.frame = CGRect(origin: retreatedOrigin, size: windowFrame.size)
            }
        })
    }

    private func scheduleAutoHideIfCursorOutside() {
        guard !isMoveMode, config.effectiveAutoHide, let display = resolvedDisplay() else { return }
        let displayed = Self.combinedDisplayedItems(pinned: config.items, openApps: openAppItems)
        let pillSize = DockGeometry.panelSize(for: config, displayedItems: displayed)
        let visiblePillFrame = DockGeometry.visibleFrame(
            for: config.placement,
            panelSize: pillSize,
            in: display.visibleFrame
        )
        if !visiblePillFrame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation) {
            autoHideController.mouseExited()
        }
    }

    private func updateMoveBannerPosition() {
        guard isMoveMode, panel.isVisible, let display = resolvedDisplay() else {
            moveBannerWindow.hide()
            return
        }
        let pillScreenRect = DockGeometry.pillFrame(fromWindowFrame: panel.frame, insets: currentPillInsets)
        moveBannerWindow.show(
            near: pillScreenRect,
            orientation: config.effectiveOrientation,
            snappedEdge: config.placement.snappedEdge,
            screenBounds: display.visibleFrame
        )
    }

    private func updateCornerRadius(for size: CGSize) {
        glassBackgroundView.cornerRadius = DockGeometry.cornerRadius(for: size)
    }

    // MARK: - DockItemStripViewDelegate

    func stripView(_ view: DockItemStripView, didUpdateGlassFrame pillFrame: CGRect) {
        glassBackgroundView.frame = pillFrame
        updateCornerRadius(for: pillFrame.size)
    }

    func stripView(_ view: DockItemStripView, didClickItem item: DockItem) {
        tooltipWindow.hide()
        Launcher.shared.open(item)
    }

    func stripViewDidClickEmptyState(_ view: DockItemStripView) {
        delegate?.panelControllerDidRequestAddItems(self)
    }

    func stripView(_ view: DockItemStripView, didHoverLabel text: String?, anchorRectInStrip: CGRect?) {
        guard !isDraggingPanel, !isMoveMode,
              let text,
              let anchorRectInStrip,
              let display = resolvedDisplay() else {
            tooltipWindow.hide()
            return
        }

        let rectInWindow = stripView.convert(anchorRectInStrip, to: nil)
        let screenRect = panel.convertToScreen(rectInWindow)

        tooltipWindow.show(
            text: text,
            anchorScreenRect: screenRect,
            orientation: config.effectiveOrientation,
            snappedEdge: config.placement.snappedEdge,
            screenBounds: display.visibleFrame
        )
    }

    func stripView(_ view: DockItemStripView, didUpdateRemoveHint showRemove: Bool, anchorRectInStrip: CGRect?) {
        guard showRemove, let anchorRectInStrip, let display = resolvedDisplay() else {
            tooltipWindow.hide()
            return
        }
        let rectInWindow = stripView.convert(anchorRectInStrip, to: nil)
        let screenRect = panel.convertToScreen(rectInWindow)
        tooltipWindow.show(
            text: "Release to Remove",
            anchorScreenRect: screenRect,
            orientation: config.effectiveOrientation,
            snappedEdge: config.placement.snappedEdge,
            screenBounds: display.visibleFrame
        )
    }

    /// Native macOS Dock right-click menu layout:
    /// Options ▸ (✓ Keep in Dock [or unchecked for open app], Move to ▸, Copy to ▸, Show in Finder)
    /// ─────────
    /// Hide + Quit (running) / Open (not running)
    func stripView(_ view: DockItemStripView, contextMenuForItem item: DockItem, isTransientOpenApp: Bool) -> NSMenu {
        tooltipWindow.hide()
        let menu = NSMenu()

        switch item.kind {
        case .app:
            let isRunning = isTransientOpenApp || (item.bundleIdentifier.map { runningBundleIDs.contains($0) } ?? false)

            let optionsMenuItem = NSMenuItem(title: "Options", action: nil, keyEquivalent: "")
            optionsMenuItem.submenu = makeOptionsSubmenu(for: item, isTransientOpenApp: isTransientOpenApp)
            menu.addItem(optionsMenuItem)

            menu.addItem(.separator())

            if isRunning {
                let hideItem = NSMenuItem(title: "Hide", action: #selector(contextHideApp(_:)), keyEquivalent: "")
                hideItem.target = self
                hideItem.representedObject = item
                menu.addItem(hideItem)

                let quitItem = NSMenuItem(title: "Quit", action: #selector(contextQuitApp(_:)), keyEquivalent: "")
                quitItem.target = self
                quitItem.representedObject = item
                menu.addItem(quitItem)
            } else {
                let openItem = NSMenuItem(title: "Open", action: #selector(contextOpenItem(_:)), keyEquivalent: "")
                openItem.target = self
                openItem.representedObject = item
                menu.addItem(openItem)
            }

        case .file, .folder:
            let optionsMenuItem = NSMenuItem(title: "Options", action: nil, keyEquivalent: "")
            optionsMenuItem.submenu = makeOptionsSubmenu(for: item, isTransientOpenApp: false)
            menu.addItem(optionsMenuItem)

            menu.addItem(.separator())

            let openItem = NSMenuItem(title: "Open", action: #selector(contextOpenItem(_:)), keyEquivalent: "")
            openItem.target = self
            openItem.representedObject = item
            menu.addItem(openItem)

        case .separator:
            let removeItem = NSMenuItem(title: "Remove Separator", action: #selector(contextRemoveItem(_:)), keyEquivalent: "")
            removeItem.target = self
            removeItem.representedObject = item
            menu.addItem(removeItem)
        }

        return menu
    }

    private func makeOptionsSubmenu(for item: DockItem, isTransientOpenApp: Bool) -> NSMenu {
        let submenu = NSMenu()

        if isTransientOpenApp {
            let keepItem = NSMenuItem(title: "Keep in Dock", action: #selector(contextPinOpenApp(_:)), keyEquivalent: "")
            keepItem.target = self
            keepItem.representedObject = item
            keepItem.state = .off
            submenu.addItem(keepItem)
        } else {
            let keepItem = NSMenuItem(title: "Keep in Dock", action: #selector(contextRemoveItem(_:)), keyEquivalent: "")
            keepItem.target = self
            keepItem.representedObject = item
            keepItem.state = .on
            submenu.addItem(keepItem)
        }

        if item.kind == .app {
            let openAtLoginItem = NSMenuItem(title: "Open at Login", action: #selector(contextToggleOpenAtLogin(_:)), keyEquivalent: "")
            openAtLoginItem.target = self
            openAtLoginItem.representedObject = item
            let enabled = delegate?.panelController(self, isOpenAtLogin: item) ?? false
            openAtLoginItem.state = enabled ? .on : .off
            submenu.addItem(openAtLoginItem)
        }

        if let otherDocks = delegate?.panelController(self, otherDocksFor: dockID), !otherDocks.isEmpty {
            let moveMenuItem = NSMenuItem(title: isTransientOpenApp ? "Keep in Another Dock" : "Move to", action: nil, keyEquivalent: "")
            let moveSubmenu = NSMenu()
            for targetDock in otherDocks {
                let entry = NSMenuItem(title: targetDock.name, action: #selector(contextMoveItemToDock(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = ItemTransferPayload(item: item, isTransientOpenApp: isTransientOpenApp, targetDockID: targetDock.id)
                moveSubmenu.addItem(entry)
            }
            moveMenuItem.submenu = moveSubmenu
            submenu.addItem(moveMenuItem)

            if !isTransientOpenApp {
                let copyMenuItem = NSMenuItem(title: "Copy to", action: nil, keyEquivalent: "")
                let copySubmenu = NSMenu()
                for targetDock in otherDocks {
                    let entry = NSMenuItem(title: targetDock.name, action: #selector(contextCopyItemToDock(_:)), keyEquivalent: "")
                    entry.target = self
                    entry.representedObject = ItemTransferPayload(item: item, isTransientOpenApp: false, targetDockID: targetDock.id)
                    copySubmenu.addItem(entry)
                }
                copyMenuItem.submenu = copySubmenu
                submenu.addItem(copyMenuItem)
            }
        }

        let finderItem = NSMenuItem(title: "Show in Finder", action: #selector(contextShowInFinder(_:)), keyEquivalent: "")
        finderItem.target = self
        finderItem.representedObject = item
        submenu.addItem(finderItem)

        return submenu
    }

    func stripViewContextMenuForEmptyArea(_ view: DockItemStripView) -> NSMenu {
        tooltipWindow.hide()
        let menu = NSMenu()

        let addItems = NSMenuItem(title: "Add Items…", action: #selector(contextAddItems), keyEquivalent: "")
        addItems.target = self
        menu.addItem(addItems)

        let addSep = NSMenuItem(title: "Add Separator", action: #selector(contextAddSeparator), keyEquivalent: "")
        addSep.target = self
        menu.addItem(addSep)

        menu.addItem(.separator())

        let moveTitle = isMoveMode ? "Done Moving Dock" : "Move Dock"
        let moveItem = NSMenuItem(title: moveTitle, action: #selector(contextToggleMoveMode), keyEquivalent: "")
        moveItem.target = self
        menu.addItem(moveItem)

        let snapItem = NSMenuItem(title: "Snap to Edge", action: nil, keyEquivalent: "")
        let snapSubmenu = NSMenu()
        let currentEdge = config.placement.snappedEdge
        for edge in DockConfig.Edge.allCases {
            let edgeItem = NSMenuItem(title: edge.displayName, action: #selector(contextSnapToEdge(_:)), keyEquivalent: "")
            edgeItem.target = self
            edgeItem.representedObject = edge.rawValue
            edgeItem.state = currentEdge == edge ? .on : .off
            snapSubmenu.addItem(edgeItem)
        }
        snapSubmenu.addItem(.separator())
        let floatItem = NSMenuItem(title: "Floating", action: #selector(contextSnapToEdge(_:)), keyEquivalent: "")
        floatItem.target = self
        floatItem.representedObject = nil
        floatItem.state = currentEdge == nil ? .on : .off
        snapSubmenu.addItem(floatItem)
        snapItem.submenu = snapSubmenu
        menu.addItem(snapItem)

        let flipTitle = config.orientation == .horizontal ? "Switch to Vertical" : "Switch to Horizontal"
        let flipItem = NSMenuItem(title: flipTitle, action: #selector(contextToggleOrientation), keyEquivalent: "")
        flipItem.target = self
        menu.addItem(flipItem)

        let magItem = NSMenuItem(title: "Magnification", action: #selector(contextToggleMagnification), keyEquivalent: "")
        magItem.target = self
        magItem.state = config.magnificationEnabled ? .on : .off
        menu.addItem(magItem)

        if config.placement.isSnapped {
            let autoHideItem = NSMenuItem(title: "Automatically Hide and Show", action: #selector(contextToggleAutoHide), keyEquivalent: "")
            autoHideItem.target = self
            autoHideItem.state = config.autoHide ? .on : .off
            menu.addItem(autoHideItem)
        }

        let manageItem = NSMenuItem(title: "Manage Docks…", action: #selector(contextManageDocks), keyEquivalent: "")
        manageItem.target = self
        menu.addItem(manageItem)

        menu.addItem(.separator())

        let newDockItem = NSMenuItem(title: "New Dock", action: #selector(contextNewDock), keyEquivalent: "")
        newDockItem.target = self
        menu.addItem(newDockItem)

        let deleteDockItem = NSMenuItem(title: "Delete This Dock", action: #selector(contextDeleteDock), keyEquivalent: "")
        deleteDockItem.target = self
        menu.addItem(deleteDockItem)

        return menu
    }

    func stripView(_ view: DockItemStripView, didDropURLs urls: [URL], at index: Int) {
        let accepted = delegate?.panelController(self, didDropURLs: urls, at: index) ?? false
        if !accepted {
            stripView.playRejectShake()
        }
    }

    func stripView(_ view: DockItemStripView, didReorderItemFrom fromIndex: Int, to toIndex: Int) {
        delegate?.panelController(self, didReorderItemFrom: fromIndex, to: toIndex)
    }

    func stripView(_ view: DockItemStripView, didDragRemoveItem item: DockItem) {
        delegate?.panelController(self, didRemoveItem: item)
    }

    func stripViewDidBeginWindowDrag(_ view: DockItemStripView, event: NSEvent) {
        guard isMoveMode else { return }
        tooltipWindow.hide()
        isDraggingPanel = true
        autoHideController.revealImmediately()
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartPanelOrigin = panel.frame.origin
        NSCursor.closedHand.push()
    }

    func stripView(_ view: DockItemStripView, didContinueWindowDrag event: NSEvent) {
        guard isDraggingPanel, isMoveMode else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - dragStartMouseLocation.x
        let dy = current.y - dragStartMouseLocation.y
        panel.setFrameOrigin(NSPoint(x: dragStartPanelOrigin.x + dx, y: dragStartPanelOrigin.y + dy))
        updateMoveBannerPosition()
    }

    func stripViewDidEndWindowDrag(_ view: DockItemStripView, event: NSEvent) {
        guard isDraggingPanel else { return }
        isDraggingPanel = false
        NSCursor.pop()

        let pillFrame = DockGeometry.pillFrame(fromWindowFrame: panel.frame, insets: currentPillInsets)
        let center = CGPoint(x: pillFrame.midX, y: pillFrame.midY)
        guard let targetDisplay = displayObserver.display(containing: center) ?? displayObserver.mainDisplay() else {
            return
        }

        let newPlacement = DockGeometry.placementForDraggedFrame(
            pillFrame,
            in: targetDisplay.visibleFrame,
            displayUUID: targetDisplay.uuid
        )

        let newOrientation: DockConfig.Orientation
        if case .snapped(let edge, _, _) = newPlacement {
            newOrientation = edge.preferredOrientation
        } else {
            newOrientation = config.orientation
        }

        delegate?.panelController(self, didUpdatePlacement: newPlacement, orientation: newOrientation)
    }

    func stripViewMouseDidEnter(_ view: DockItemStripView) {
        autoHideController.mouseEntered()
    }

    func stripViewMouseDidExit(_ view: DockItemStripView) {
        autoHideController.mouseExited()
    }

    // MARK: - Context Menu Actions

    @objc private func contextOpenItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? DockItem else { return }
        Launcher.shared.open(item)
    }

    @objc private func contextHideApp(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? DockItem else { return }
        Launcher.shared.hideApp(item)
    }

    @objc private func contextQuitApp(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? DockItem else { return }
        Launcher.shared.quitApp(item)
    }

    @objc private func contextShowInFinder(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? DockItem else { return }
        Launcher.shared.showInFinder(item)
    }

    @objc private func contextRemoveItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? DockItem else { return }
        delegate?.panelController(self, didRemoveItem: item)
    }

    @objc private func contextPinOpenApp(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? DockItem else { return }
        delegate?.panelController(self, didPinOpenApp: item)
    }

    @objc private func contextToggleOpenAtLogin(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? DockItem else { return }
        delegate?.panelController(self, didToggleOpenAtLogin: item)
    }

    @objc private func contextToggleMoveMode() {
        delegate?.panelController(self, didSetMoveMode: !isMoveMode)
    }

    @objc private func contextSnapToEdge(_ sender: NSMenuItem) {
        let edge = (sender.representedObject as? String).flatMap(DockConfig.Edge.init(rawValue:))
        delegate?.panelController(self, didRequestSnapToEdge: edge)
    }

    @objc private func contextToggleMagnification() {
        delegate?.panelControllerDidRequestToggleMagnification(self)
    }

    @objc private func contextAddItems() {
        delegate?.panelControllerDidRequestAddItems(self)
    }

    @objc private func contextAddSeparator() {
        delegate?.panelControllerDidRequestAddSeparator(self)
    }

    @objc private func contextToggleAutoHide() {
        delegate?.panelControllerDidRequestToggleAutoHide(self)
    }

    @objc private func contextToggleOrientation() {
        delegate?.panelControllerDidRequestToggleOrientation(self)
    }

    @objc private func contextNewDock() {
        delegate?.panelControllerDidRequestNewDock(self)
    }

    @objc private func contextDeleteDock() {
        delegate?.panelControllerDidRequestDeleteDock(self)
    }

    @objc private func contextMoveItemToDock(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ItemTransferPayload else { return }
        delegate?.panelController(self, didMoveItem: payload.item, isTransientOpenApp: payload.isTransientOpenApp, toDock: payload.targetDockID)
    }

    @objc private func contextCopyItemToDock(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ItemTransferPayload else { return }
        delegate?.panelController(self, didCopyItem: payload.item, toDock: payload.targetDockID)
    }

    @objc private func contextManageDocks() {
        delegate?.panelControllerDidRequestManageDocks(self)
    }
}

private final class ItemTransferPayload {
    let item: DockItem
    let isTransientOpenApp: Bool
    let targetDockID: UUID

    init(item: DockItem, isTransientOpenApp: Bool, targetDockID: UUID) {
        self.item = item
        self.isTransientOpenApp = isTransientOpenApp
        self.targetDockID = targetDockID
    }
}
