import AppKit
import CoreFoundation
import Foundation

struct SystemDockPreferences: Codable, Equatable {
    var hadAutoHide: Bool
    var autoHide: Bool
    var autoHideDelay: Double?
}

/// Safely suppresses and restores the macOS system Dock using `com.apple.dock` preferences
/// (`autohide = true` + `autohide-delay = 1000`), keeping Mission Control, Spaces, Wallpaper,
/// and Cmd+Tab fully intact while preventing the built-in Dock from popping up over Dock+.
@MainActor
enum SystemDockController {
    private static let dockDomain = "com.apple.dock" as CFString
    private static let autoHideKey = "autohide" as CFString
    private static let autoHideDelayKey = "autohide-delay" as CFString
    private static let suppressDelaySeconds: Double = 1000.0
    private static let suppressedSentinelThreshold: Double = 500.0

    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static func captureCurrentPreferences() -> SystemDockPreferences {
        let rawAutoHide = CFPreferencesCopyValue(
            autoHideKey,
            dockDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        let hadAutoHide = rawAutoHide != nil
        let autoHide = (rawAutoHide as? Bool) ?? ((rawAutoHide as? NSNumber)?.boolValue ?? false)

        let rawDelay = CFPreferencesCopyValue(
            autoHideDelayKey,
            dockDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        var delay: Double?
        if let num = rawDelay as? NSNumber {
            let value = num.doubleValue
            // Never snapshot our own suppressed sentinel delay as the user's original setting
            if value < suppressedSentinelThreshold {
                delay = value
            }
        }

        return SystemDockPreferences(
            hadAutoHide: hadAutoHide,
            autoHide: autoHide,
            autoHideDelay: delay
        )
    }

    static func disableSystemDock() {
        guard !isRunningUnitTests else { return }

        CFPreferencesSetValue(
            autoHideKey,
            kCFBooleanTrue,
            dockDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        CFPreferencesSetValue(
            autoHideDelayKey,
            NSNumber(value: Float(suppressDelaySeconds)),
            dockDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        CFPreferencesSynchronize(
            dockDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )

        restartSystemDock()
    }

    static func restoreSystemDock(to snapshot: SystemDockPreferences?) {
        guard !isRunningUnitTests else { return }

        if let snapshot {
            if snapshot.hadAutoHide {
                CFPreferencesSetValue(
                    autoHideKey,
                    snapshot.autoHide ? kCFBooleanTrue : kCFBooleanFalse,
                    dockDomain,
                    kCFPreferencesCurrentUser,
                    kCFPreferencesAnyHost
                )
            } else {
                CFPreferencesSetValue(
                    autoHideKey,
                    nil,
                    dockDomain,
                    kCFPreferencesCurrentUser,
                    kCFPreferencesAnyHost
                )
            }

            if let delay = snapshot.autoHideDelay {
                CFPreferencesSetValue(
                    autoHideDelayKey,
                    NSNumber(value: Float(delay)),
                    dockDomain,
                    kCFPreferencesCurrentUser,
                    kCFPreferencesAnyHost
                )
            } else {
                CFPreferencesSetValue(
                    autoHideDelayKey,
                    nil,
                    dockDomain,
                    kCFPreferencesCurrentUser,
                    kCFPreferencesAnyHost
                )
            }
        } else {
            // Safe fallback if no snapshot exists: clear the delay override and turn autohide off
            CFPreferencesSetValue(
                autoHideDelayKey,
                nil,
                dockDomain,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            )
            CFPreferencesSetValue(
                autoHideKey,
                kCFBooleanFalse,
                dockDomain,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            )
        }

        CFPreferencesSynchronize(
            dockDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )

        restartSystemDock()
    }

    private static func restartSystemDock() {
        let dockApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
        if !dockApps.isEmpty {
            for app in dockApps {
                app.terminate()
            }
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["Dock"]
        try? task.run()
    }
}
