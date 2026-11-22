import SwiftUI

struct SettingsView: View {
    @ObservedObject var dockManager: DockManager
    @ObservedObject private var launchAtLogin = LaunchAtLoginService.shared

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 3) {
                    Toggle("Disable system Dock", isOn: Binding(
                        get: { dockManager.config.disableSystemDock },
                        set: { dockManager.setDisableSystemDock($0) }
                    ))
                    Text("Hides the built-in macOS Dock while Dock+ is running and automatically restores it when you quit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Toggle("Start new docks from current Dock", isOn: Binding(
                        get: { dockManager.config.startNewDocksFromCurrentDock },
                        set: { dockManager.setStartNewDocksFromCurrentDock($0) }
                    ))
                    Text("New docks begin with the apps pinned to your macOS Dock.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Toggle("Launch Dock+ at login", isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { _ = launchAtLogin.setEnabled($0) }
                    ))
                    Text("Automatically start Dock+ when you log in to your Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 270)
    }
}
