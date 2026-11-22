#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    double blurRadius;
    double blurOpacity;
    double aberrationAmount;
    double faceBlack;
    double faceWhite;
    double faceSaturation;
    double faceFillRed;
    double faceFillGreen;
    double faceFillBlue;
    double faceFillAlpha;
    double keyFillHighlightAmount;
    double rimSpecularOpacity;
    double rimRed;
    double rimGreen;
    double rimBlue;
    double rimKeyAlpha;
    double rimFillAlpha;
} DPLiquidGlassAppearanceParams;

/// Objective-C QuartzCore engine that reproduces Apple's macOS 26/27 Liquid Glass pipeline
/// using `CABackdropLayer`, `CASDFLayer`, `CASDFElementLayer`, `CASDFOutputEffect`,
/// `CASDFKeyFillHighlightEffect`, `CAPortalLayer`, and `CAFilter` (`glassBackground` +
/// `vibrantColorMatrix`).
@interface DPLiquidGlassEngine : NSObject

/// Returns nil on macOS versions prior to macOS 26 where QuartzCore SDF Liquid Glass layers are unavailable.
- (nullable instancetype)initWithHostLayer:(CALayer *)hostLayer
                              cornerRadius:(CGFloat)cornerRadius
                                 groupName:(NSString *)groupName NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (void)updateLayoutForBounds:(CGRect)bounds cornerRadius:(CGFloat)cornerRadius;
- (void)applyAppearanceParams:(DPLiquidGlassAppearanceParams)params;

@end

NS_ASSUME_NONNULL_END
