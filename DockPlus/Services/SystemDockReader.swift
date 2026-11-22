import Foundation

/// Reads the user's current macOS Dock pinned items (read-only).
enum SystemDockReader {
    static var defaultPlistURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Preferences/com.apple.dock.plist", isDirectory: false)
    }

    static func readCurrentDockItems(from plistURL: URL = defaultPlistURL) -> [DockItem] {
        guard FileManager.default.isReadableFile(atPath: plistURL.path),
              let data = try? Data(contentsOf: plistURL) else {
            return []
        }
        return parse(plistData: data)
    }

    static func parse(plistData: Data) -> [DockItem] {
        guard let plist = try? PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        ) as? [String: Any] else {
            return []
        }

        var items: [DockItem] = []
        var seenPaths = Set<String>()

        if let persistentApps = plist["persistent-apps"] as? [[String: Any]] {
            for entry in persistentApps {
                if let url = extractFileURL(from: entry) {
                    let path = url.standardizedFileURL.path
                    guard !seenPaths.contains(path) else { continue }
                    seenPaths.insert(path)
                    items.append(DockItem(kind: .app, path: path))
                }
            }
        }

        if let persistentOthers = plist["persistent-others"] as? [[String: Any]] {
            for entry in persistentOthers {
                if let url = extractFileURL(from: entry) {
                    let path = url.standardizedFileURL.path
                    guard !seenPaths.contains(path) else { continue }
                    seenPaths.insert(path)
                    items.append(DockItem(kind: DockItem.classify(url: url), path: path))
                }
            }
        }

        return items
    }

    private static func extractFileURL(from entry: [String: Any]) -> URL? {
        guard let tileData = entry["tile-data"] as? [String: Any],
              let fileData = tileData["file-data"] as? [String: Any],
              let urlString = fileData["_CFURLString"] as? String else {
            return nil
        }

        if let url = URL(string: urlString), url.isFileURL {
            return url
        }
        if urlString.hasPrefix("/") {
            return URL(fileURLWithPath: urlString)
        }
        return nil
    }
}
