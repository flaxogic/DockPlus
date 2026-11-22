import Foundation

struct DockConfig: Codable, Identifiable, Equatable {
    struct TintColor: Codable, Equatable {
        var red: Double
        var green: Double
        var blue: Double

        init(red: Double, green: Double, blue: Double) {
            self.red = min(max(red, 0.0), 1.0)
            self.green = min(max(green, 0.0), 1.0)
            self.blue = min(max(blue, 0.0), 1.0)
        }
    }

    enum Orientation: String, Codable, CaseIterable, Equatable {
        case horizontal
        case vertical

        var displayName: String {
            switch self {
            case .horizontal: return "Horizontal"
            case .vertical: return "Vertical"
            }
        }
    }

    enum Edge: String, Codable, CaseIterable, Equatable {
        case bottom
        case top
        case left
        case right

        var preferredOrientation: Orientation {
            switch self {
            case .bottom, .top: return .horizontal
            case .left, .right: return .vertical
            }
        }

        var displayName: String {
            switch self {
            case .bottom: return "Bottom"
            case .top: return "Top"
            case .left: return "Left"
            case .right: return "Right"
            }
        }
    }

    enum Placement: Codable, Equatable {
        case floating(x: Double, y: Double, displayUUID: String?)
        case snapped(edge: Edge, offset: Double, displayUUID: String?)

        var displayUUID: String? {
            switch self {
            case .floating(_, _, let uuid): return uuid
            case .snapped(_, _, let uuid): return uuid
            }
        }

        var isSnapped: Bool {
            if case .snapped = self { return true }
            return false
        }

        var snappedEdge: Edge? {
            if case .snapped(let edge, _, _) = self { return edge }
            return nil
        }
    }

    static let minIconSize: Double = 32
    static let maxIconSize: Double = 80
    static let defaultIconSize: Double = 52

    static let minMagnificationScale: Double = 1.15
    static let maxMagnificationScale: Double = 2.0
    static let defaultMagnificationScale: Double = 1.55

    /// `0.0` = Opaque, `1.0` = Ultra-clear transparent glass.
    static let defaultGlassTransparency: Double = 0.85

    var id: UUID
    var name: String
    var items: [DockItem]
    var orientation: Orientation
    var placement: Placement
    var iconSize: Double
    var magnificationEnabled: Bool
    var magnificationScale: Double
    var autoHide: Bool
    var isVisible: Bool
    var glassTransparency: Double
    var tintColor: TintColor?

    init(
        id: UUID = UUID(),
        name: String = "Dock 1",
        items: [DockItem] = [],
        orientation: Orientation = .horizontal,
        placement: Placement = .snapped(edge: .bottom, offset: 0, displayUUID: nil),
        iconSize: Double = DockConfig.defaultIconSize,
        magnificationEnabled: Bool = true,
        magnificationScale: Double = DockConfig.defaultMagnificationScale,
        autoHide: Bool = false,
        isVisible: Bool = true,
        glassTransparency: Double = DockConfig.defaultGlassTransparency,
        tintColor: TintColor? = nil
    ) {
        self.id = id
        self.name = name
        self.items = items
        self.orientation = orientation
        self.placement = placement
        self.iconSize = min(max(iconSize, Self.minIconSize), Self.maxIconSize)
        self.magnificationEnabled = magnificationEnabled
        self.magnificationScale = min(max(magnificationScale, Self.minMagnificationScale), Self.maxMagnificationScale)
        self.autoHide = autoHide
        self.isVisible = isVisible
        self.glassTransparency = min(max(glassTransparency, 0.0), 1.0)
        self.tintColor = tintColor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.items = try container.decode([DockItem].self, forKey: .items)
        self.orientation = try container.decode(Orientation.self, forKey: .orientation)
        self.placement = try container.decode(Placement.self, forKey: .placement)
        let rawSize = try container.decodeIfPresent(Double.self, forKey: .iconSize) ?? Self.defaultIconSize
        self.iconSize = min(max(rawSize, Self.minIconSize), Self.maxIconSize)
        self.magnificationEnabled = try container.decodeIfPresent(Bool.self, forKey: .magnificationEnabled) ?? true
        let rawMag = try container.decodeIfPresent(Double.self, forKey: .magnificationScale) ?? Self.defaultMagnificationScale
        self.magnificationScale = min(max(rawMag, Self.minMagnificationScale), Self.maxMagnificationScale)
        self.autoHide = try container.decodeIfPresent(Bool.self, forKey: .autoHide) ?? false
        self.isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        let rawTransparency = try container.decodeIfPresent(Double.self, forKey: .glassTransparency) ?? Self.defaultGlassTransparency
        self.glassTransparency = min(max(rawTransparency, 0.0), 1.0)
        self.tintColor = try container.decodeIfPresent(TintColor.self, forKey: .tintColor)
    }

    var effectiveOrientation: Orientation {
        orientation
    }

    var effectiveAutoHide: Bool {
        autoHide && placement.isSnapped
    }

    static func starterDock(name: String = "Dock 1") -> DockConfig {
        DockConfig(
            name: name,
            items: [],
            orientation: .horizontal,
            placement: .snapped(edge: .bottom, offset: 0, displayUUID: nil),
            iconSize: defaultIconSize,
            magnificationEnabled: true,
            magnificationScale: defaultMagnificationScale,
            autoHide: false,
            isVisible: true,
            glassTransparency: defaultGlassTransparency,
            tintColor: nil
        )
    }
}
