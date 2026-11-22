import AppKit
import Combine
import Foundation

struct RunningAppInfo: Equatable, Hashable {
    let bundleIdentifier: String
    let bundleURL: URL
    let name: String
}

/// Observes NSWorkspace launch/terminate notifications AND runningApplications KVO for instant updates with zero polling.
@MainActor
final class RunningAppObserver: ObservableObject {
    @Published private(set) var runningBundleIDs: Set<String> = []
    @Published private(set) var regularRunningApps: [RunningAppInfo] = []

    private var observers: [NSObjectProtocol] = []
    private var runningAppsKVO: NSKeyValueObservation?

    init() {
        refreshSnapshot()
        let center = NSWorkspace.shared.notificationCenter

        let launchObs = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshSnapshot()
            }
        }

        let terminateObs = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let terminatedPID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            Task { @MainActor [weak self] in
                // Exclude the terminated PID immediately to avoid AppKit's brief runningApplications lag
                self?.refreshSnapshot(excludingPID: terminatedPID)
            }
        }

        observers = [launchObs, terminateObs]

        // KVO on NSWorkspace.runningApplications catches crashes, force-quits, and delayed exits instantly
        runningAppsKVO = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshSnapshot()
            }
        }
    }

    deinit {
        runningAppsKVO?.invalidate()
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
    }

    func isRunning(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return runningBundleIDs.contains(bundleIdentifier)
    }

    func refreshSnapshot(excludingPID: pid_t? = nil) {
        let ownBundleID = Bundle.main.bundleIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter { app in
            if let excludingPID, app.processIdentifier == excludingPID {
                return false
            }
            return !app.isTerminated
        }

        let newBundleIDs = Set(apps.compactMap { $0.bundleIdentifier })
        if newBundleIDs != runningBundleIDs {
            runningBundleIDs = newBundleIDs
        }

        var seen = Set<String>()
        var regular: [RunningAppInfo] = []
        for app in apps {
            guard app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier,
                  bundleID != ownBundleID,
                  let url = app.bundleURL?.standardizedFileURL,
                  !seen.contains(bundleID) else {
                continue
            }
            seen.insert(bundleID)
            let name = app.localizedName ?? url.deletingPathExtension().lastPathComponent
            regular.append(RunningAppInfo(bundleIdentifier: bundleID, bundleURL: url, name: name))
        }
        if regular != regularRunningApps {
            regularRunningApps = regular
        }
    }
}
