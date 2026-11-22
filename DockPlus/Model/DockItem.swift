import Foundation
import UniformTypeIdentifiers

struct DockItem: Codable, Identifiable, Equatable, Hashable {
    enum Kind: String, Codable, Equatable, Hashable {
        case app
        case file
        case folder
        case separator
    }

    var id: UUID
    var kind: Kind
    var path: String?
    var labelOverride: String?

    init(
        id: UUID = UUID(),
        kind: Kind,
        path: String? = nil,
        labelOverride: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.path = path
        self.labelOverride = labelOverride
    }

    static func separator() -> DockItem {
        DockItem(kind: .separator, path: nil, labelOverride: nil)
    }

    /// Classifies a filesystem URL by bundle / UTI metadata rather than extension string matching alone.
    static func from(url: URL) -> DockItem {
        let standardizedURL = url.standardizedFileURL
        let kind = classify(url: standardizedURL)
        return DockItem(kind: kind, path: standardizedURL.path)
    }

    static func classify(url: URL) -> Kind {
        let keys: Set<URLResourceKey> = [.isApplicationKey, .isDirectoryKey, .isPackageKey, .contentTypeKey]
        if let values = try? url.resourceValues(forKeys: keys) {
            if values.isApplication == true {
                return .app
            }
            if let contentType = values.contentType, contentType.conforms(to: .applicationBundle) {
                return .app
            }
            if values.isDirectory == true && values.isPackage != true {
                return .folder
            }
        }
        // Fallback when file does not exist on disk (e.g. during unit tests or unmounted volumes)
        if url.pathExtension.lowercased() == "app" {
            return .app
        }
        return .file
    }

    var fileURL: URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    var existsOnDisk: Bool {
        guard kind != .separator else { return true }
        guard let path else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    var displayName: String {
        if let labelOverride, !labelOverride.isEmpty {
            return labelOverride
        }
        if kind == .separator {
            return "Separator"
        }
        guard let url = fileURL else { return "Unknown" }
        if kind == .app {
            let name = FileManager.default.displayName(atPath: url.path)
            if name.hasSuffix(".app") {
                return String(name.dropLast(4))
            }
            return name
        }
        return url.lastPathComponent
    }

    var bundleIdentifier: String? {
        guard kind == .app, let url = fileURL else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }
}
