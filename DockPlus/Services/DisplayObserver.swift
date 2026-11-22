import AppKit
import Combine
import CoreGraphics
import Foundation

struct DisplayInfo: Identifiable, Equatable, Hashable {
    let uuid: String
    let displayID: CGDirectDisplayID
    let name: String
    let frame: CGRect
    let visibleFrame: CGRect
    let isMain: Bool

    var id: String { uuid }
}

@MainActor
final class DisplayObserver: ObservableObject {
    @Published private(set) var displays: [DisplayInfo] = []

    var onDisplaysChanged: (() -> Void)?

    private var screenObserver: NSObjectProtocol?

    init() {
        refreshDisplays()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshDisplays()
                self?.onDisplaysChanged?()
            }
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    func refreshDisplays() {
        let mainID = CGMainDisplayID()
        displays = NSScreen.screens.compactMap { screen in
            guard let displayID = Self.displayID(for: screen),
                  let uuid = Self.displayUUID(for: displayID) else {
                return nil
            }
            return DisplayInfo(
                uuid: uuid,
                displayID: displayID,
                name: screen.localizedName,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                isMain: displayID == mainID
            )
        }
    }

    func display(forUUID uuid: String) -> DisplayInfo? {
        displays.first(where: { $0.uuid == uuid })
    }

    func mainDisplay() -> DisplayInfo? {
        displays.first(where: { $0.isMain }) ?? displays.first
    }

    func display(containing point: CGPoint) -> DisplayInfo? {
        if let match = displays.first(where: { $0.frame.contains(point) }) {
            return match
        }
        return displays.min { lhs, rhs in
            distance(from: point, to: lhs.frame) < distance(from: point, to: rhs.frame)
        }
    }

    func screen(forUUID uuid: String) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let id = Self.displayID(for: screen) else { return false }
            return Self.displayUUID(for: id) == uuid
        }
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }

    static func displayUUID(for displayID: CGDirectDisplayID) -> String? {
        guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, cfUUID) as String
    }

    static func displayUUID(for screen: NSScreen) -> String? {
        guard let id = displayID(for: screen) else { return nil }
        return displayUUID(for: id)
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }
}
