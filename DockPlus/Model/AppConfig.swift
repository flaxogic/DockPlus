import Foundation

struct AppConfig: Codable, Equatable {
    var docks: [DockConfig]
    var startNewDocksFromCurrentDock: Bool
    var openAppsDockID: UUID?
    var openAtLoginPaths: [String]
    var disableSystemDock: Bool
    var savedSystemDockPreferences: SystemDockPreferences?

    init(
        docks: [DockConfig] = [DockConfig.starterDock()],
        startNewDocksFromCurrentDock: Bool = false,
        openAppsDockID: UUID? = nil,
        openAtLoginPaths: [String] = [],
        disableSystemDock: Bool = false,
        savedSystemDockPreferences: SystemDockPreferences? = nil
    ) {
        self.docks = docks
        self.startNewDocksFromCurrentDock = startNewDocksFromCurrentDock
        self.openAppsDockID = openAppsDockID
        self.openAtLoginPaths = openAtLoginPaths
        self.disableSystemDock = disableSystemDock
        self.savedSystemDockPreferences = savedSystemDockPreferences
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.docks = try container.decodeIfPresent([DockConfig].self, forKey: .docks) ?? [DockConfig.starterDock()]
        self.startNewDocksFromCurrentDock = try container.decodeIfPresent(Bool.self, forKey: .startNewDocksFromCurrentDock) ?? false
        self.openAppsDockID = try container.decodeIfPresent(UUID.self, forKey: .openAppsDockID)
        self.openAtLoginPaths = try container.decodeIfPresent([String].self, forKey: .openAtLoginPaths) ?? []
        self.disableSystemDock = try container.decodeIfPresent(Bool.self, forKey: .disableSystemDock) ?? false
        self.savedSystemDockPreferences = try container.decodeIfPresent(SystemDockPreferences.self, forKey: .savedSystemDockPreferences)
    }
}
