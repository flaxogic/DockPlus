import AppKit
import QuartzCore

/// Authentic macOS Liquid Glass surface powered by `DPLiquidGlassEngine` (Objective-C QuartzCore
/// SDF pipeline: `CABackdropLayer` + `CASDFLayer` + `CASDFElementLayer` + `CASDFOutputEffect`
/// + `CAFilter("glassBackground")` + `CASDFKeyFillHighlightEffect` + `vibrantColorMatrix`).
///
/// Supports global blur level plus per-dock transparency (`0.0` Opaque → `1.0` Clear) and custom
/// tint color, stays 100% active on non-activating floating panels, and falls back cleanly to
/// `NSVisualEffectView` on macOS 14–25.
@MainActor
final class LiquidGlassView: NSView {
    enum Variant {
        /// Liquid Glass for the main dock pill.
        case dockPill
        /// Slightly higher-legibility Liquid Glass for floating tooltips and Move Mode banners.
        case floatingHUD
    }

    var cornerRadius: CGFloat {
        didSet {
            if abs(oldValue - cornerRadius) > 0.05 {
                needsLayout = true
            }
        }
    }

    /// Per-dock glass transparency in `0.0...1.0` (`0.0` = Opaque/Frosted, `1.0` = Ultra-clear).
    var transparency: Double {
        didSet {
            let clamped = min(max(transparency, 0.0), 1.0)
            if clamped != transparency {
                transparency = clamped
                return
            }
            if abs(oldValue - clamped) > 0.0005 {
                updateAppearanceParameters()
            }
        }
    }

    /// Optional per-dock sRGB tint color (`nil` = neutral clear glass).
    var tintColor: DockConfig.TintColor? {
        didSet {
            if oldValue != tintColor {
                updateAppearanceParameters()
            }
        }
    }

    let contentView = NSView()

    private let variant: Variant
    private let glassGroupID = "DockPlus.LiquidGlass.\(UUID().uuidString)"
    private let shadowPad: CGFloat = 48

    private var engine: DPLiquidGlassEngine?
    private var shadowLayer: CALayer?
    private var shadowCutoutMask: CAShapeLayer?
    private var fallbackEffectView: NSVisualEffectView?
    private var fallbackTintLayer: CALayer?

    init(
        frame frameRect: NSRect,
        cornerRadius: CGFloat = 18,
        variant: Variant = .dockPill,
        transparency: Double = DockConfig.defaultGlassTransparency,
        tintColor: DockConfig.TintColor? = nil
    ) {
        self.cornerRadius = cornerRadius
        self.variant = variant
        self.transparency = min(max(transparency, 0.0), 1.0)
        self.tintColor = tintColor
        super.init(frame: frameRect)
        setupHierarchy()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupHierarchy() {
        wantsLayer = true
        layerUsesCoreImageFilters = false
        layer?.masksToBounds = false

        if let rootLayer = layer {
            // Exterior-only optical elevation shadow for dock pills (fits cleanly inside the
            // 12 pt window headroom and is even-odd masked so zero dark tint bleeds through glass).
            if variant == .dockPill {
                let shadowHost = CALayer()
                shadowHost.masksToBounds = false
                shadowHost.shadowColor = NSColor.black.cgColor
                shadowHost.shadowOpacity = 0.26
                shadowHost.shadowRadius = 7.5
                shadowHost.shadowOffset = CGSize(width: 0, height: -2.5)

                let cutout = CAShapeLayer()
                cutout.fillRule = .evenOdd
                cutout.fillColor = NSColor.white.cgColor
                shadowHost.mask = cutout
                rootLayer.addSublayer(shadowHost)
                self.shadowLayer = shadowHost
                self.shadowCutoutMask = cutout
            }

            if let glassEngine = DPLiquidGlassEngine(
                hostLayer: rootLayer,
                cornerRadius: cornerRadius,
                groupName: glassGroupID
            ) {
                self.engine = glassEngine
            } else {
                shadowLayer?.removeFromSuperlayer()
                shadowLayer = nil
                shadowCutoutMask = nil
                setupFallbackVisualEffect()
            }
        } else {
            setupFallbackVisualEffect()
        }

        contentView.frame = bounds
        contentView.autoresizingMask = [.width, .height]
        addSubview(contentView)

        updateAppearanceParameters()
        needsLayout = true
    }

    private func setupFallbackVisualEffect() {
        let effect = NSVisualEffectView(frame: bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerCurve = .continuous
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.masksToBounds = true
        addSubview(effect)

        let tint = CALayer()
        tint.frame = bounds
        tint.cornerCurve = .continuous
        tint.cornerRadius = cornerRadius
        tint.masksToBounds = true
        layer?.addSublayer(tint)

        self.fallbackEffectView = effect
        self.fallbackTintLayer = tint
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearanceParameters()
    }

    override func layout() {
        super.layout()
        let rect = bounds
        guard rect.width > 0, rect.height > 0 else { return }

        let minDim = min(rect.width, rect.height)
        let clampedRadius = min(cornerRadius, minDim / 2)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if let engine {
            engine.updateLayout(forBounds: rect, cornerRadius: clampedRadius)

            if let shadowLayer, let shadowCutoutMask {
                let expandedFrame = rect.insetBy(dx: -shadowPad, dy: -shadowPad)
                let pillInShadowCoords = CGRect(x: shadowPad, y: shadowPad, width: rect.width, height: rect.height)
                let pillPath = CGPath(
                    roundedRect: pillInShadowCoords,
                    cornerWidth: clampedRadius,
                    cornerHeight: clampedRadius,
                    transform: nil
                )
                shadowLayer.frame = expandedFrame
                shadowLayer.shadowPath = pillPath

                let localBounds = CGRect(origin: .zero, size: expandedFrame.size)
                let maskPath = CGMutablePath()
                maskPath.addRect(localBounds)
                maskPath.addPath(pillPath)
                shadowCutoutMask.frame = localBounds
                shadowCutoutMask.path = maskPath
            }
        } else {
            fallbackEffectView?.layer?.cornerRadius = clampedRadius
            fallbackTintLayer?.frame = rect
            fallbackTintLayer?.cornerRadius = clampedRadius
        }

        CATransaction.commit()
    }

    private func updateAppearanceParameters() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let effectiveTransparency: Double = (variant == .dockPill) ? transparency : min(transparency, 0.78)
        let opacityFactor = 1.0 - effectiveTransparency // 0.0 = 100% Clear, 1.0 = Opaque

        // Smooth optical blur curve driven directly by per-dock transparency:
        // 100% Clear -> 0 blur; 85% default -> whisper-light crystal glass; 0% -> rich frosted glass
        let blurRadius = pow(opacityFactor, 1.15) * 5.5
        let blurOpacity = opacityFactor <= 0.001 ? 0.0 : min(1.0, pow(opacityFactor, 0.65))

        // Resolve glass body fill RGB + alpha and specular rim RGB
        let fillRed: Double
        let fillGreen: Double
        let fillBlue: Double
        let fillAlpha: Double
        let rimRed: Double
        let rimGreen: Double
        let rimBlue: Double

        if let tint = tintColor {
            fillRed = tint.red
            fillGreen = tint.green
            fillBlue = tint.blue
            fillAlpha = 0.07 + pow(opacityFactor, 0.92) * 0.78
            rimRed = 1.0 * 0.72 + tint.red * 0.28
            rimGreen = 1.0 * 0.72 + tint.green * 0.28
            rimBlue = 1.0 * 0.72 + tint.blue * 0.28
        } else if isDark {
            let darkMix = min(opacityFactor / 0.35, 1.0)
            fillRed = 0.96 * (1.0 - darkMix) + 0.10 * darkMix
            fillGreen = 0.96 * (1.0 - darkMix) + 0.10 * darkMix
            fillBlue = 0.98 * (1.0 - darkMix) + 0.12 * darkMix
            fillAlpha = 0.015 + pow(opacityFactor, 1.12) * 0.84
            rimRed = 1.0
            rimGreen = 1.0
            rimBlue = 1.0
        } else {
            fillRed = 0.98
            fillGreen = 0.98
            fillBlue = 1.0
            fillAlpha = 0.015 + pow(opacityFactor, 1.12) * 0.84
            rimRed = 1.0
            rimGreen = 1.0
            rimBlue = 1.0
        }

        guard let engine else {
            fallbackEffectView?.alphaValue = CGFloat(0.20 + opacityFactor * 0.80)
            fallbackTintLayer?.backgroundColor = NSColor(
                srgbRed: fillRed,
                green: fillGreen,
                blue: fillBlue,
                alpha: fillAlpha
            ).cgColor
            return
        }

        let params: DPLiquidGlassAppearanceParams
        if isDark {
            params = DPLiquidGlassAppearanceParams(
                blurRadius: blurRadius,
                blurOpacity: blurOpacity,
                aberrationAmount: (variant == .dockPill) ? 1.35 : 0.85,
                faceBlack: 0.02 + opacityFactor * 0.04,
                faceWhite: 0.90 - opacityFactor * 0.08,
                faceSaturation: 1.12 + opacityFactor * 0.12,
                faceFillRed: fillRed,
                faceFillGreen: fillGreen,
                faceFillBlue: fillBlue,
                faceFillAlpha: fillAlpha,
                keyFillHighlightAmount: 0.45,
                rimSpecularOpacity: (variant == .dockPill) ? 0.58 : 0.48,
                rimRed: rimRed,
                rimGreen: rimGreen,
                rimBlue: rimBlue,
                rimKeyAlpha: 0.34,
                rimFillAlpha: 0.22
            )
        } else {
            params = DPLiquidGlassAppearanceParams(
                blurRadius: blurRadius,
                blurOpacity: blurOpacity,
                aberrationAmount: (variant == .dockPill) ? 1.35 : 0.85,
                faceBlack: 0.08 + opacityFactor * 0.12,
                faceWhite: 0.97,
                faceSaturation: 1.10 + opacityFactor * 0.10,
                faceFillRed: fillRed,
                faceFillGreen: fillGreen,
                faceFillBlue: fillBlue,
                faceFillAlpha: fillAlpha,
                keyFillHighlightAmount: 0.52,
                rimSpecularOpacity: (variant == .dockPill) ? 0.72 : 0.58,
                rimRed: rimRed,
                rimGreen: rimGreen,
                rimBlue: rimBlue,
                rimKeyAlpha: 0.48,
                rimFillAlpha: 0.32
            )
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        engine.apply(params)
        CATransaction.commit()
    }
}
