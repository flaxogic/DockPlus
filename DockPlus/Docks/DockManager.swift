import AppKit
import Combine
import Foundation

struct LastRemovalUndo {
    let dockID: UUID
    let item: DockItem
    let index: Int
}

@MainActor
final class DockManager: ObservableObject, DockPanelControllerDelegate {
    @Published private(set) var config: AppConfig
    @Published private(set) var allDocksHidden: Bool = false
    @Published private(set) var movingDockIDs: Set<UUID> = []
    @Published private(set) var lastRemovalUndo: LastRemovalUndo?

    let configStore: ConfigStore
    let displayObserver: DisplayObserver
    let runningAppObserver: RunningAppObserver

    var onOpenManageDocks: ((UUID?) -> Void)?

    private var controllers: [UUID: DockPanelController] = [:]
    private var cancellables: Set<AnyCancellable> = []

    init(
        configStore: ConfigStore = ConfigStore(),
        displayObserver: DisplayObserver? = nil,
        runningAppObserver: RunningAppObserver? = nil
    ) {
        let resolvedDisplayObserver = displayObserver ?? DisplayObserver()
        let resolvedRunningAppObserver = runningAppObserver ?? RunningAppObserver()
        self.configStore = configStore
        self.displayObserver = resolvedDisplayObserver
        self.runningAppObserver = resolvedRunningAppObserver
        self.config = configStore.load()

        setupObservers()
        syncControllers()
    }

    var docks: [DockConfig] {
        config.docks
    }

    var isAnyDockMoving: Bool {
        !movingDockIDs.isEmpty
    }

    func dock(for id: UUID) -> DockConfig? {
        config.docks.first(where: { $0.id == id })
    }

    func flushPersistence() {
        configStore.flushSave(config)
    }

    // MARK: - Observers

    private func setupObservers() {
        runningAppObserver.$runningBundleIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ids in
                guard let self else { return }
                for controller in self.controllers.values {
                    controller.updateRunningApps(ids)
                }
            }
            .store(in: &cancellables)

        runningAppObserver.$regularRunningApps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncControllers()
            }
            .store(in: &cancellables)

        displayObserver.onDisplaysChanged = { [weak self] in
            guard let self else { return }
            for controller in self.controllers.values {
                controller.handleDisplaysChanged()
            }
        }
    }

    private func openAppItems(for dock: DockConfig) -> [DockItem] {
        guard config.openAppsDockID == dock.id else { return [] }

        // Exclude apps already pinned to any dock so open apps aren't duplicated
        var pinnedPaths = Set<String>()
        var pinnedBundleIDs = Set<String>()
        for d in config.docks {
            for item in d.items {
                if let path = item.path {
                    pinnedPaths.insert(URL(fileURLWithPath: path).standardizedFileURL.path)
                }
                if let bid = item.bundleIdentifier {
                    pinnedBundleIDs.insert(bid)
                }
            }
        }

        return runningAppObserver.regularRunningApps.compactMap { appInfo in
            let path = appInfo.bundleURL.standardizedFileURL.path
            if pinnedPaths.contains(path) || pinnedBundleIDs.contains(appInfo.bundleIdentifier) {
                return nil
            }
            return DockItem(kind: .app, path: path)
        }
    }

    private func syncControllers() {
        let validIDs = Set(config.docks.map(\.id))

        for (id, controller) in controllers where !validIDs.contains(id) {
            controller.close()
            controllers.removeValue(forKey: id)
            movingDockIDs.remove(id)
        }

        for dock in config.docks {
            let openItems = openAppItems(for: dock)
            if let existing = controllers[dock.id] {
                existing.update(config: dock, openAppItems: openItems)
                existing.setMoveMode(movingDockIDs.contains(dock.id))
            } else {
                let controller = DockPanelController(
                    config: dock,
                    openAppItems: openItems,
                    displayObserver: displayObserver,
                    runningBundleIDs: runningAppObserver.runningBundleIDs
                )
                controller.delegate = self
                controller.updateGlobalHidden(allDocksHidden)
                controller.setMoveMode(movingDockIDs.contains(dock.id))
                controllers[dock.id] = controller
            }
        }
    }

    private func commitChange() {
        syncControllers()
        configStore.scheduleSave(config)
    }

    // MARK: - Move Mode

    func setMoveMode(_ enabled: Bool, for dockID: UUID) {
        if enabled {
            movingDockIDs.insert(dockID)
        } else {
            movingDockIDs.remove(dockID)
        }
        controllers[dockID]?.setMoveMode(enabled)
    }

    func toggleMoveModeForAllDocks() {
        if isAnyDockMoving {
            movingDockIDs.removeAll()
            for controller in controllers.values {
                controller.setMoveMode(false)
            }
        } else {
            for dock in config.docks where dock.isVisible {
                movingDockIDs.insert(dock.id)
                controllers[dock.id]?.setMoveMode(true)
            }
        }
    }

    // MARK: - Dock CRUD & Overall Settings

    @discardableResult
    func addDock(name: String? = nil) -> DockConfig {
        let nextNumber = config.docks.count + 1
        let dockName = name ?? "Dock \(nextNumber)"
        let offset = Double((config.docks.count % 4) * 36)
        let initialItems = config.startNewDocksFromCurrentDock ? SystemDockReader.readCurrentDockItems() : []
        let newDock = DockConfig(
            name: dockName,
            items: initialItems,
            orientation: .horizontal,
            placement: .snapped(edge: .bottom, offset: offset, displayUUID: nil),
            iconSize: DockConfig.defaultIconSize,
            autoHide: false,
            isVisible: true
        )
        config.docks.append(newDock)
        commitChange()
        return newDock
    }

    func setStartNewDocksFromCurrentDock(_ enabled: Bool) {
        config.startNewDocksFromCurrentDock = enabled
        commitChange()
    }

    func setDisableSystemDock(_ enabled: Bool) {
        guard config.disableSystemDock != enabled else { return }
        config.disableSystemDock = enabled

        if enabled {
            if config.savedSystemDockPreferences == nil {
                config.savedSystemDockPreferences = SystemDockController.captureCurrentPreferences()
            }
            configStore.flushSave(config)
            SystemDockController.disableSystemDock()
        } else {
            let snapshot = config.savedSystemDockPreferences
            config.savedSystemDockPreferences = nil
            configStore.flushSave(config)
            SystemDockController.restoreSystemDock(to: snapshot)
        }
    }

    func applySystemDockStateOnLaunch() {
        guard config.disableSystemDock else { return }
        if config.savedSystemDockPreferences == nil {
            config.savedSystemDockPreferences = SystemDockController.captureCurrentPreferences()
            configStore.flushSave(config)
        }
        SystemDockController.disableSystemDock()
    }

    func restoreSystemDockOnTerminate() {
        guard config.disableSystemDock else { return }
        let snapshot = config.savedSystemDockPreferences
        config.savedSystemDockPreferences = nil
        configStore.flushSave(config)
        SystemDockController.restoreSystemDock(to: snapshot)
    }

    func setOpenAppsDockID(_ dockID: UUID?) {
        config.openAppsDockID = dockID
        commitChange()
    }

    func deleteDock(id: UUID) {
        guard config.docks.count > 1 else { return }
        config.docks.removeAll(where: { $0.id == id })
        if config.openAppsDockID == id {
            config.openAppsDockID = nil
        }
        if lastRemovalUndo?.dockID == id {
            lastRemovalUndo = nil
        }
        movingDockIDs.remove(id)
        commitChange()
    }

    func updateDock(_ updated: DockConfig) {
        guard let idx = config.docks.firstIndex(where: { $0.id == updated.id }) else { return }
        config.docks[idx] = updated
        commitChange()
    }

    func toggleDockVisibility(id: UUID) {
        guard let idx = config.docks.firstIndex(where: { $0.id == id }) else { return }
        config.docks[idx].isVisible.toggle()
        if !config.docks[idx].isVisible {
            movingDockIDs.remove(id)
        }
        commitChange()
    }

    func toggleAllDocksHidden() {
        allDocksHidden.toggle()
        if allDocksHidden {
            movingDockIDs.removeAll()
        }
        for controller in controllers.values {
            controller.setMoveMode(false)
            controller.updateGlobalHidden(allDocksHidden)
        }
    }

    func snapDock(_ dockID: UUID, to edge: DockConfig.Edge?) {
        guard let idx = config.docks.firstIndex(where: { $0.id == dockID }) else { return }
        let currentDisplayUUID = config.docks[idx].placement.displayUUID
        if let edge {
            config.docks[idx].placement = .snapped(edge: edge, offset: 0, displayUUID: currentDisplayUUID)
            config.docks[idx].orientation = edge.preferredOrientation
        } else {
            let display = currentDisplayUUID.flatMap { displayObserver.display(forUUID: $0) } ?? displayObserver.mainDisplay()
            let visible = display?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            let size = DockGeometry.panelSize(for: config.docks[idx])
            let centerX = visible.midX - size.width / 2
            let centerY = visible.midY - size.height / 2
            config.docks[idx].placement = .floating(x: Double(centerX), y: Double(centerY), displayUUID: currentDisplayUUID)
        }
        commitChange()
    }

    func assignDock(_ dockID: UUID, toDisplayUUID displayUUID: String?) {
        guard let idx = config.docks.firstIndex(where: { $0.id == dockID }) else { return }
        switch config.docks[idx].placement {
        case .snapped(let edge, _, _):
            config.docks[idx].placement = .snapped(edge: edge, offset: 0, displayUUID: displayUUID)
        case .floating:
            let display = displayUUID.flatMap { displayObserver.display(forUUID: $0) } ?? displayObserver.mainDisplay()
            let visible = display?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            let size = DockGeometry.panelSize(for: config.docks[idx])
            let centerX = visible.midX - size.width / 2
            let centerY = visible.midY - size.height / 2
            config.docks[idx].placement = .floating(x: Double(centerX), y: Double(centerY), displayUUID: displayUUID)
        }
        commitChange()
    }

    // MARK: - Item Management

    @discardableResult
    func addItems(urls: [URL], to dockID: UUID, at index: Int? = nil) -> Bool {
        guard let dockIndex = config.docks.firstIndex(where: { $0.id == dockID }) else { return false }

        let existingPaths = Set(config.docks[dockIndex].items.compactMap { $0.path })
        var newItems: [DockItem] = []
        var seenInBatch = Set<String>()

        for url in urls {
            let standardized = url.standardizedFileURL
            let path = standardized.path
            if existingPaths.contains(path) || seenInBatch.contains(path) {
                continue
            }
            seenInBatch.insert(path)
            newItems.append(DockItem.from(url: standardized))
        }

        guard !newItems.isEmpty else {
            return false
        }

        let insertAt = min(max(index ?? config.docks[dockIndex].items.count, 0), config.docks[dockIndex].items.count)
        config.docks[dockIndex].items.insert(contentsOf: newItems, at: insertAt)
        commitChange()
        return true
    }

    func addSeparator(to dockID: UUID, at index: Int? = nil) {
        guard let dockIndex = config.docks.firstIndex(where: { $0.id == dockID }) else { return }
        let insertAt = min(max(index ?? config.docks[dockIndex].items.count, 0), config.docks[dockIndex].items.count)
        config.docks[dockIndex].items.insert(DockItem.separator(), at: insertAt)
        commitChange()
    }

    func removeItem(itemID: UUID, from dockID: UUID) {
        guard let dockIndex = config.docks.firstIndex(where: { $0.id == dockID }),
              let itemIndex = config.docks[dockIndex].items.firstIndex(where: { $0.id == itemID }) else {
            return
        }
        let removed = config.docks[dockIndex].items.remove(at: itemIndex)
        lastRemovalUndo = LastRemovalUndo(dockID: dockID, item: removed, index: itemIndex)
        commitChange()
    }

    func undoLastRemoval() {
        guard let undo = lastRemovalUndo,
              let dockIndex = config.docks.firstIndex(where: { $0.id == undo.dockID }) else {
            return
        }
        let insertAt = min(max(undo.index, 0), config.docks[dockIndex].items.count)
        config.docks[dockIndex].items.insert(undo.item, at: insertAt)
        lastRemovalUndo = nil
        commitChange()
    }

    func reorderItem(in dockID: UUID, from fromIndex: Int, to toIndex: Int) {
        guard let dockIndex = config.docks.firstIndex(where: { $0.id == dockID }) else { return }
        var items = config.docks[dockIndex].items
        guard fromIndex >= 0, fromIndex < items.count, toIndex >= 0, toIndex < items.count, fromIndex != toIndex else {
            return
        }
        let item = items.remove(at: fromIndex)
        items.insert(item, at: toIndex)
        config.docks[dockIndex].items = items
        commitChange()
    }

    func moveItem(_ item: DockItem, from sourceDockID: UUID, isTransientOpenApp: Bool, to targetDockID: UUID) {
        guard sourceDockID != targetDockID,
              let targetIndex = config.docks.firstIndex(where: { $0.id == targetDockID }) else {
            return
        }

        if let path = item.path,
           config.docks[targetIndex].items.contains(where: { $0.path == path }) {
            NSSound.beep()
            return
        }

        if !isTransientOpenApp, let sourceIndex = config.docks.firstIndex(where: { $0.id == sourceDockID }) {
            config.docks[sourceIndex].items.removeAll(where: { $0.id == item.id })
        }
        let movedCopy = DockItem(kind: item.kind, path: item.path, labelOverride: item.labelOverride)
        config.docks[targetIndex].items.append(movedCopy)
        commitChange()
    }

    func copyItem(_ item: DockItem, to targetDockID: UUID) {
        guard let targetIndex = config.docks.firstIndex(where: { $0.id == targetDockID }) else { return }

        if let path = item.path,
           config.docks[targetIndex].items.contains(where: { $0.path == path }) {
            NSSound.beep()
            return
        }

        let copy = DockItem(kind: item.kind, path: item.path, labelOverride: item.labelOverride)
        config.docks[targetIndex].items.append(copy)
        commitChange()
    }

    func presentAddItemsPanel(for dockID: UUID) {
        let panel = NSOpenPanel()
        panel.title = "Add Items to Dock"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            _ = addItems(urls: panel.urls, to: dockID)
        }
    }

    // MARK: - DockPanelControllerDelegate

    func panelController(_ controller: DockPanelController, didUpdatePlacement placement: DockConfig.Placement, orientation: DockConfig.Orientation) {
        guard let idx = config.docks.firstIndex(where: { $0.id == controller.dockID }) else { return }
        config.docks[idx].placement = placement
        config.docks[idx].orientation = orientation
        commitChange()
    }

    func panelController(_ controller: DockPanelController, didDropURLs urls: [URL], at index: Int) -> Bool {
        addItems(urls: urls, to: controller.dockID, at: index)
    }

    func panelController(_ controller: DockPanelController, didReorderItemFrom fromIndex: Int, to toIndex: Int) {
        reorderItem(in: controller.dockID, from: fromIndex, to: toIndex)
    }

    func panelController(_ controller: DockPanelController, didRemoveItem item: DockItem) {
        removeItem(itemID: item.id, from: controller.dockID)
    }

    func isOpenAtLogin(item: DockItem) -> Bool {
        guard let path = item.fileURL?.standardizedFileURL.path else { return false }
        return config.openAtLoginPaths.contains(path)
    }

    func toggleOpenAtLogin(for item: DockItem) {
        guard item.kind == .app, let path = item.fileURL?.standardizedFileURL.path else { return }
        if let idx = config.openAtLoginPaths.firstIndex(of: path) {
            config.openAtLoginPaths.remove(at: idx)
        } else {
            config.openAtLoginPaths.append(path)
            // Ensure Dock+ itself launches at login so marked apps open at login
            if !LaunchAtLoginService.shared.isEnabled {
                _ = LaunchAtLoginService.shared.setEnabled(true)
            }
        }
        commitChange()
    }

    func launchOpenAtLoginApps() {
        for path in config.openAtLoginPaths {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else { continue }
            if let bid = Bundle(url: url)?.bundleIdentifier,
               !NSRunningApplication.runningApplications(withBundleIdentifier: bid).isEmpty {
                continue
            }
            let openConfig = NSWorkspace.OpenConfiguration()
            openConfig.activates = false
            openConfig.createsNewApplicationInstance = false
            NSWorkspace.shared.openApplication(at: url, configuration: openConfig, completionHandler: nil)
        }
    }

    func panelController(_ controller: DockPanelController, didPinOpenApp item: DockItem) {
        guard let url = item.fileURL else { return }
        _ = addItems(urls: [url], to: controller.dockID)
    }

    func panelController(_ controller: DockPanelController, isOpenAtLogin item: DockItem) -> Bool {
        isOpenAtLogin(item: item)
    }

    func panelController(_ controller: DockPanelController, didToggleOpenAtLogin item: DockItem) {
        toggleOpenAtLogin(for: item)
    }

    func panelController(_ controller: DockPanelController, didSetMoveMode enabled: Bool) {
        setMoveMode(enabled, for: controller.dockID)
    }

    func panelController(_ controller: DockPanelController, didRequestSnapToEdge edge: DockConfig.Edge?) {
        snapDock(controller.dockID, to: edge)
    }

    func panelControllerDidRequestToggleMagnification(_ controller: DockPanelController) {
        guard let idx = config.docks.firstIndex(where: { $0.id == controller.dockID }) else { return }
        config.docks[idx].magnificationEnabled.toggle()
        commitChange()
    }

    func panelController(_ controller: DockPanelController, otherDocksFor dockID: UUID) -> [DockConfig] {
        config.docks.filter { $0.id != dockID }
    }

    func panelController(_ controller: DockPanelController, didMoveItem item: DockItem, isTransientOpenApp: Bool, toDock targetDockID: UUID) {
        moveItem(item, from: controller.dockID, isTransientOpenApp: isTransientOpenApp, to: targetDockID)
    }

    func panelController(_ controller: DockPanelController, didCopyItem item: DockItem, toDock targetDockID: UUID) {
        copyItem(item, to: targetDockID)
    }

    func panelControllerDidRequestAddItems(_ controller: DockPanelController) {
        presentAddItemsPanel(for: controller.dockID)
    }

    func panelControllerDidRequestAddSeparator(_ controller: DockPanelController) {
        addSeparator(to: controller.dockID)
    }

    func panelControllerDidRequestToggleAutoHide(_ controller: DockPanelController) {
        guard let idx = config.docks.firstIndex(where: { $0.id == controller.dockID }) else { return }
        config.docks[idx].autoHide.toggle()
        commitChange()
    }

    func panelControllerDidRequestToggleOrientation(_ controller: DockPanelController) {
        guard let idx = config.docks.firstIndex(where: { $0.id == controller.dockID }) else { return }
        config.docks[idx].orientation = config.docks[idx].orientation == .horizontal ? .vertical : .horizontal
        commitChange()
    }

    func panelControllerDidRequestNewDock(_ controller: DockPanelController) {
        _ = addDock()
    }

    func panelControllerDidRequestDeleteDock(_ controller: DockPanelController) {
        deleteDock(id: controller.dockID)
    }

    func panelControllerDidRequestManageDocks(_ controller: DockPanelController) {
        onOpenManageDocks?(controller.dockID)
    }
}
