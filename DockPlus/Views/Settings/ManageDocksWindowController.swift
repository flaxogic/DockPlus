import AppKit
import SwiftUI

@MainActor
final class ManageDocksWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let dockManager: DockManager
    private let viewModel: ManageDocksViewModel

    init(dockManager: DockManager) {
        self.dockManager = dockManager
        self.viewModel = ManageDocksViewModel(dockManager: dockManager)
        super.init()
    }

    func show(selectingDock dockID: UUID? = nil) {
        if let dockID {
            viewModel.selectedDockID = dockID
        }

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = ManageDocksView(dockManager: dockManager, viewModel: viewModel)
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Manage Docks"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = false
        window.setContentSize(NSSize(width: 620, height: 500))
        window.minSize = NSSize(width: 560, height: 420)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        dockManager.flushPersistence()
    }
}

@MainActor
final class ManageDocksViewModel: ObservableObject {
    @Published var selectedDockID: UUID?

    init(dockManager: DockManager) {
        self.selectedDockID = dockManager.docks.first?.id
    }
}
