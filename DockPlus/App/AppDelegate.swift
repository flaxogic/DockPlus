import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var dockManager: DockManager!
    private var menuController: MenuController!
    private var manageDocksWindowController: ManageDocksWindowController!
    private var settingsWindowController: SettingsWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        dockManager = DockManager()
        manageDocksWindowController = ManageDocksWindowController(dockManager: dockManager)
        settingsWindowController = SettingsWindowController(dockManager: dockManager)

        dockManager.onOpenManageDocks = { [weak self] dockID in
            self?.manageDocksWindowController.show(selectingDock: dockID)
        }

        menuController = MenuController(
            dockManager: dockManager,
            onOpenManageDocks: { [weak self] dockID in
                self?.manageDocksWindowController.show(selectingDock: dockID)
            },
            onOpenSettings: { [weak self] in
                self?.settingsWindowController.show()
            }
        )

        setupEditMenu()
        dockManager.applySystemDockStateOnLaunch()
        dockManager.launchOpenAtLoginApps()
    }

    func applicationWillTerminate(_ notification: Notification) {
        dockManager?.restoreSystemDockOnTerminate()
        dockManager?.flushPersistence()
    }

    private func setupEditMenu() {
        let mainMenu = NSMenu()
        mainMenu.addItem(NSMenuItem())

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: #selector(handleUndoAction), keyEquivalent: "z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func handleUndoAction() {
        if dockManager.lastRemovalUndo != nil {
            dockManager.undoLastRemoval()
        }
    }
}
