import AppKit
import Foundation

@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let dockManager: DockManager
    private let onOpenManageDocks: (UUID?) -> Void
    private let onOpenSettings: () -> Void

    init(
        dockManager: DockManager,
        onOpenManageDocks: @escaping (UUID?) -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.dockManager = dockManager
        self.onOpenManageDocks = onOpenManageDocks
        self.onOpenSettings = onOpenSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "Dock+")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Dock+"
        }

        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let newDockItem = NSMenuItem(title: "New Dock", action: #selector(newDockAction), keyEquivalent: "n")
        newDockItem.target = self
        menu.addItem(newDockItem)

        menu.addItem(.separator())

        for dock in dockManager.docks {
            let toggleItem = NSMenuItem(title: dock.name, action: #selector(toggleDockAction(_:)), keyEquivalent: "")
            toggleItem.target = self
            toggleItem.representedObject = dock.id
            toggleItem.state = dock.isVisible ? .on : .off
            menu.addItem(toggleItem)
        }

        menu.addItem(.separator())

        let moveTitle = dockManager.isAnyDockMoving ? "Done Moving Docks" : "Move Docks"
        let moveItem = NSMenuItem(title: moveTitle, action: #selector(toggleMoveModeAction), keyEquivalent: "")
        moveItem.target = self
        moveItem.state = dockManager.isAnyDockMoving ? .on : .off
        menu.addItem(moveItem)

        let toggleAllTitle = dockManager.allDocksHidden ? "Show All Docks" : "Hide All Docks"
        let toggleAllItem = NSMenuItem(title: toggleAllTitle, action: #selector(toggleAllAction), keyEquivalent: "")
        toggleAllItem.target = self
        menu.addItem(toggleAllItem)

        if let undo = dockManager.lastRemovalUndo {
            let undoItem = NSMenuItem(
                title: "Undo Remove \"\(undo.item.displayName)\"",
                action: #selector(undoRemovalAction),
                keyEquivalent: "z"
            )
            undoItem.target = self
            menu.addItem(undoItem)
        }

        menu.addItem(.separator())

        let manageDocksItem = NSMenuItem(title: "Manage Docks…", action: #selector(openManageDocksAction), keyEquivalent: "m")
        manageDocksItem.target = self
        menu.addItem(manageDocksItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Dock+", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func newDockAction() {
        _ = dockManager.addDock()
    }

    @objc private func toggleDockAction(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        dockManager.toggleDockVisibility(id: id)
    }

    @objc private func toggleMoveModeAction() {
        dockManager.toggleMoveModeForAllDocks()
    }

    @objc private func toggleAllAction() {
        dockManager.toggleAllDocksHidden()
    }

    @objc private func undoRemovalAction() {
        dockManager.undoLastRemoval()
    }

    @objc private func openManageDocksAction() {
        onOpenManageDocks(nil)
    }

    @objc private func openSettingsAction() {
        onOpenSettings()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}
