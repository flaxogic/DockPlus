import Foundation

final class ConfigStore {
    let directoryURL: URL
    let configURL: URL
    let backupURL: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let debounceInterval: TimeInterval
    private var pendingSaveWorkItem: DispatchWorkItem?
    private let saveQueue = DispatchQueue(label: "com.flaxogic.dockplus.configstore", qos: .utility)

    init(directoryURL: URL? = nil, fileManager: FileManager = .default, debounceInterval: TimeInterval = 0.3) {
        self.fileManager = fileManager
        self.debounceInterval = debounceInterval

        let dir: URL
        if let directoryURL {
            dir = directoryURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
            dir = appSupport.appendingPathComponent("DockPlus", isDirectory: true)
        }
        self.directoryURL = dir
        self.configURL = dir.appendingPathComponent("docks.json", isDirectory: false)
        self.backupURL = dir.appendingPathComponent("docks.json.bak", isDirectory: false)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    func load() -> AppConfig {
        if let decoded = decode(from: configURL) {
            return decoded
        }
        if let backup = decode(from: backupURL) {
            try? saveImmediately(backup)
            return backup
        }
        return AppConfig(docks: [DockConfig.starterDock()])
    }

    func scheduleSave(_ config: AppConfig) {
        pendingSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            try? self.saveImmediately(config)
        }
        pendingSaveWorkItem = workItem
        saveQueue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    func flushSave(_ config: AppConfig) {
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        saveQueue.sync {
            try? self.saveImmediately(config)
        }
    }

    func saveImmediately(_ config: AppConfig) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode(config)

        let tempURL = directoryURL.appendingPathComponent("docks.json.tmp.\(UUID().uuidString)")
        try data.write(to: tempURL, options: .atomic)

        if fileManager.fileExists(atPath: configURL.path) {
            if fileManager.fileExists(atPath: backupURL.path) {
                try? fileManager.removeItem(at: backupURL)
            }
            try? fileManager.copyItem(at: configURL, to: backupURL)
            _ = try fileManager.replaceItemAt(configURL, withItemAt: tempURL)
        } else {
            try fileManager.moveItem(at: tempURL, to: configURL)
        }
    }

    private func decode(from url: URL) -> AppConfig? {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              var config = try? decoder.decode(AppConfig.self, from: data) else {
            return nil
        }
        if config.docks.isEmpty {
            config.docks = [DockConfig.starterDock()]
        }
        return config
    }
}
