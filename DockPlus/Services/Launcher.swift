import AppKit
import Foundation

@MainActor
final class Launcher {
    static let shared = Launcher()

    private init() {}

    func open(_ item: DockItem) {
        guard item.kind != .separator, let url = item.fileURL else { return }
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSSound.beep()
            return
        }

        switch item.kind {
        case .app:
            openOrActivateApp(at: url)
        case .file:
            NSWorkspace.shared.open(url)
        case .folder:
            NSWorkspace.shared.open(url)
        case .separator:
            break
        }
    }

    private func openOrActivateApp(at url: URL) {
        if let bundleID = Bundle(url: url)?.bundleIdentifier,
           let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            if runningApp.isHidden {
                runningApp.unhide()
            }
            runningApp.activate(options: [])
            // Re-open via NSWorkspace so apps with no visible windows reopen their default window
            // without launching a second instance.
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            config.createsNewApplicationInstance = false
            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
    }

    func hideApp(_ item: DockItem) {
        guard let bundleID = item.bundleIdentifier,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return
        }
        app.hide()
    }

    func quitApp(_ item: DockItem) {
        guard let bundleID = item.bundleIdentifier,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return
        }
        app.terminate()
    }

    func showInFinder(_ item: DockItem) {
        guard let url = item.fileURL else { return }
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
