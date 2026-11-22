import AppKit
import Foundation

/// Caches Retina-crisp item icons keyed by (path, size, scale) and invalidates when files change.
@MainActor
final class IconCache {
    static let shared = IconCache()

    private struct CacheKey: Hashable {
        let path: String
        let size: Int
        let scale: Int
    }

    private var imageCache: [CacheKey: NSImage] = [:]
    private var cgImageCache: [CacheKey: CGImage] = [:]
    private var fileWatchers: [String: DispatchSourceFileSystemObject] = [:]

    private init() {}

    func icon(for path: String, size: CGFloat, scale: CGFloat = 2.0) -> NSImage {
        let intSize = max(Int(round(size)), 16)
        let intScale = max(Int(round(scale)), 1)
        let key = CacheKey(path: path, size: intSize, scale: intScale)
        if let cached = imageCache[key] {
            return cached
        }

        let image: NSImage
        if FileManager.default.fileExists(atPath: path) {
            let workspaceIcon = NSWorkspace.shared.icon(forFile: path)
            image = Self.renderCrispImage(from: workspaceIcon, pointSize: CGFloat(intSize))
            watchPathIfNeeded(path)
        } else {
            image = Self.missingItemIcon(size: CGFloat(intSize))
        }

        imageCache[key] = image
        return image
    }

    func cgIcon(for path: String, size: CGFloat, scale: CGFloat = 2.0) -> CGImage? {
        let intSize = max(Int(round(size)), 16)
        let intScale = max(Int(round(scale)), 1)
        let key = CacheKey(path: path, size: intSize, scale: intScale)
        if let cached = cgImageCache[key] {
            return cached
        }

        let nsImage = icon(for: path, size: CGFloat(intSize), scale: CGFloat(intScale))
        var rect = NSRect(x: 0, y: 0, width: intSize, height: intSize)
        let hints: [NSImageRep.HintKey: Any] = [
            .ctm: AffineTransform(scale: CGFloat(intScale))
        ]
        if let cgImage = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: hints) {
            cgImageCache[key] = cgImage
            return cgImage
        }
        return nil
    }

    func invalidate(path: String) {
        imageCache = imageCache.filter { $0.key.path != path }
        cgImageCache = cgImageCache.filter { $0.key.path != path }
    }

    func clearAll() {
        imageCache.removeAll()
        cgImageCache.removeAll()
        for source in fileWatchers.values {
            source.cancel()
        }
        fileWatchers.removeAll()
    }

    private static func renderCrispImage(from source: NSImage, pointSize: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
    }

    static func missingItemIcon(size: CGFloat) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: size * 0.62, weight: .regular)
        let symbol = NSImage(systemSymbolName: "questionmark.square.dashed", accessibilityDescription: "Not found")?
            .withSymbolConfiguration(config)
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            if let symbol {
                let drawRect = NSRect(
                    x: (rect.width - symbol.size.width) / 2,
                    y: (rect.height - symbol.size.height) / 2,
                    width: symbol.size.width,
                    height: symbol.size.height
                )
                symbol.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 0.55)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private func watchPathIfNeeded(_ path: String) {
        guard fileWatchers[path] == nil else { return }
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.delete, .rename, .write, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.invalidate(path: path)
            self?.stopWatching(path: path)
        }
        source.setCancelHandler {
            close(fd)
        }
        fileWatchers[path] = source
        source.resume()
    }

    private func stopWatching(path: String) {
        if let source = fileWatchers.removeValue(forKey: path) {
            source.cancel()
        }
    }
}
