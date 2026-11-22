#import "LiquidGlassCore.h"
#import <objc/message.h>

typedef struct {
    float m11, m12, m13, m14, m15;
    float m21, m22, m23, m24, m25;
    float m31, m32, m33, m34, m35;
    float m41, m42, m43, m44, m45;
} DPCAColorMatrix;

static id _Nullable DPMakeCAFilter(NSString *type) {
    Class filterClass = NSClassFromString(@"CAFilter");
    SEL sel = NSSelectorFromString(@"filterWithType:");
    if (!filterClass || ![filterClass respondsToSelector:sel]) {
        return nil;
    }
    return ((id (*)(id, SEL, NSString *))objc_msgSend)(filterClass, sel, type);
}

@interface DPLiquidGlassEngine ()
@property (nonatomic, strong) CALayer *backdropLayer;
@property (nonatomic, strong) CALayer *sdfOutputLayer;
@property (nonatomic, strong) CALayer *sdfElementHolder;
@property (nonatomic, strong) CALayer *sdfElementLayer;
@property (nonatomic, strong, nullable) CALayer *rimHighlightLayer;
@property (nonatomic, strong, nullable) NSObject *rimHighlightEffect;
@end

@implementation DPLiquidGlassEngine

- (nullable instancetype)initWithHostLayer:(CALayer *)hostLayer
                              cornerRadius:(CGFloat)cornerRadius
                                 groupName:(NSString *)groupName {
    Class backdropClass = NSClassFromString(@"CABackdropLayer");
    Class sdfLayerClass = NSClassFromString(@"CASDFLayer");
    Class sdfElementClass = NSClassFromString(@"CASDFElementLayer");
    Class sdfOutputEffectClass = NSClassFromString(@"CASDFOutputEffect");
    id glassFilter = DPMakeCAFilter(@"glassBackground");

    if (!backdropClass || !sdfLayerClass || !sdfElementClass || !sdfOutputEffectClass || !glassFilter) {
        return nil;
    }

    self = [super init];
    if (!self) {
        return nil;
    }

    CGRect bounds = hostLayer.bounds;

    // 1. CABackdropLayer — live WindowServer capture at native resolution
    CALayer *backdrop = [[backdropClass alloc] init];
    backdrop.name = @"@0";
    backdrop.frame = bounds;
    [backdrop setValue:@YES forKey:@"windowServerAware"];
    [backdrop setValue:@1.0 forKey:@"scale"];
    [backdrop setValue:@0.0 forKey:@"bleedAmount"];
    [backdrop setValue:@0.5 forKey:@"marginWidth"];
    [backdrop setValue:groupName forKey:@"groupName"];
    [backdrop setValue:@YES forKey:@"enabled"];
    [backdrop setValue:@NO forKey:@"allowsGroupBlending"];
    [backdrop setValue:@YES forKey:@"sourceSublayerDefinesBounds"];
    [backdrop setValue:@NO forKey:@"tracksLuma"];

    // 2. CASDFLayer ("@0") with CASDFOutputEffect — continuous-squircle Signed Distance Field
    CALayer *sdfLayer = [[sdfLayerClass alloc] init];
    sdfLayer.name = @"@0";
    sdfLayer.frame = bounds;
    [sdfLayer setValue:@8.0 forKey:@"smoothness"];
    [sdfLayer setValue:@0.0 forKey:@"effectOffset"];
    [sdfLayer setValue:@0.0 forKey:@"gaussianRadius"];
    [sdfLayer setValue:@NO forKey:@"mergeElements"];

    NSObject *outputEffect = [[sdfOutputEffectClass alloc] init];
    [outputEffect setValue:@(-10000.0) forKey:@"minimum"];
    [outputEffect setValue:@1.5 forKey:@"maximum"];
    [sdfLayer setValue:outputEffect forKey:@"effect"];

    CALayer *elemHolder = [CALayer layer];
    elemHolder.frame = CGRectZero;

    CALayer *elem = [[sdfElementClass alloc] init];
    elem.frame = bounds;
    elem.cornerRadius = cornerRadius;
    elem.cornerCurve = kCACornerCurveContinuous;
    [elem setValue:@"bounds" forKey:@"mode"];
    [elem setValue:@"union" forKey:@"operation"];
    [elem setValue:@0.0 forKey:@"gradientOvalization"];
    [elem setValue:@0.0 forKey:@"contentsZeroValueDistance"];
    [elem setValue:@1.0 forKey:@"contentsOneValueDistance"];
    [elem setValue:@YES forKey:@"hitTestsAsFill"];

    [elemHolder addSublayer:elem];
    [sdfLayer addSublayer:elemHolder];
    [backdrop addSublayer:sdfLayer];

    // 3. Configure Apple's glassBackground CAFilter
    [glassFilter setValue:@"glassBackground" forKey:@"name"];
    [glassFilter setValue:@"@0" forKey:@"inputSourceSublayerName"];

    // Blur bands
    [glassFilter setValue:@0.0 forKey:@"inputBlurDistance0"];
    [glassFilter setValue:@0.0 forKey:@"inputBlurDistance1"];
    [glassFilter setValue:@0.0 forKey:@"inputBlurDistance2"];
    [glassFilter setValue:@0.0 forKey:@"inputBlurDistance3"];
    [glassFilter setValue:@0.40 forKey:@"inputBlurOpacity0"];
    [glassFilter setValue:@0.40 forKey:@"inputBlurOpacity1"];
    [glassFilter setValue:@0.40 forKey:@"inputBlurOpacity2"];
    [glassFilter setValue:@0.40 forKey:@"inputBlurOpacity3"];
    [glassFilter setValue:@0.0 forKey:@"inputBlurFillBlurRadius"];
    [glassFilter setValue:@0.0 forKey:@"inputBlurFillDarkenOpacity"];
    [glassFilter setValue:@0.0 forKey:@"inputBlurFillLightenOpacity"];
    [glassFilter setValue:@0.0 forKey:@"inputBlurFillNormalOpacity"];
    [glassFilter setValue:@0.55 forKey:@"inputBlurRadius"];

    // Snell's-law inner SDF refraction
    [glassFilter setValue:@(-42.0) forKey:@"inputInnerRefractionAmount"];
    [glassFilter setValue:@18.0 forKey:@"inputInnerRefractionHeight"];
    [glassFilter setValue:@0.0 forKey:@"inputOuterRefractionAmount"];
    [glassFilter setValue:@0.0 forKey:@"inputOuterRefractionHeight"];
    [glassFilter setValue:@(-1.0) forKey:@"inputRefractionDistance0"];
    [glassFilter setValue:@0.0 forKey:@"inputRefractionDistance1"];
    [glassFilter setValue:@0.0 forKey:@"inputRefractionOpacity"];

    // Chromatic dispersion along curved edges
    [glassFilter setValue:@1.35 forKey:@"inputAberrationAmount"];
    [glassFilter setValue:@16.0 forKey:@"inputAberrationHeight"];
    [glassFilter setValue:@(M_PI_4) forKey:@"inputAberrationAngle"];

    // Bleed off for pure Clear Liquid Glass
    [glassFilter setValue:@0.0 forKey:@"inputBleedAmount"];
    [glassFilter setValue:@0.0 forKey:@"inputBleedHeight"];
    [glassFilter setValue:@0.0 forKey:@"inputBleedBlurRadius"];
    [glassFilter setValue:@0.0 forKey:@"inputBleedOpacity"];
    [glassFilter setValue:@1.0 forKey:@"inputBleedDistance0"];
    [glassFilter setValue:@0.0 forKey:@"inputBleedDistance1"];
    [glassFilter setValue:@1.0 forKey:@"inputBleedDarkenBlend"];

    // Hardware SDF key-fill specular highlight inside glassBackground
    [glassFilter setValue:@0.48 forKey:@"inputKeyFillHighlightAmount"];
    [glassFilter setValue:@(M_PI_2) forKey:@"inputKeyFillHighlightAngle"];
    [glassFilter setValue:@(-0.25) forKey:@"inputKeyFillHighlightColorBias"];
    [glassFilter setValue:@(-0.5) forKey:@"inputKeyFillHighlightEffectOffset"];
    [glassFilter setValue:@0.65 forKey:@"inputKeyFillHighlightHeight"];
    [glassFilter setValue:@1.308996938995747 forKey:@"inputKeyFillHighlightSpread"];
    [glassFilter setValue:@1.308996938995747 forKey:@"inputKeyFillHighlightSpreadSDR"];

    // Face & clamping defaults
    [glassFilter setValue:@YES forKey:@"inputClamp"];
    [glassFilter setValue:@NO forKey:@"inputClampPreserveHue"];
    [glassFilter setValue:@1.0 forKey:@"inputFaceOpacity"];
    [glassFilter setValue:@1.0 forKey:@"inputFaceColorMatrixMaxLuma"];
    [glassFilter setValue:@1.0 forKey:@"inputFaceColorMatrixMaxLumaSDR"];
    [glassFilter setValue:@1.0 forKey:@"inputSDRGradientDistance0"];
    [glassFilter setValue:@1.0 forKey:@"inputSDRGradientDistance1"];
    [glassFilter setValue:@NO forKey:@"inputSDRHoldingToneEnabled"];
    [glassFilter setValue:@1.0 forKey:@"inputSDRHoldingToneWhite"];
    [glassFilter setValue:@0.0 forKey:@"inputShadowOpacity"];
    [glassFilter setValue:@9999.0 forKey:@"inputMaxHeadroom"];

    backdrop.filters = @[glassFilter];
    [hostLayer addSublayer:backdrop];

    // 4. Opposing diagonal crystalline SDF rim highlight (Apple's CASDFKeyFillHighlightEffect +
    // exact vibrantColorMatrix saturation/luminance boost, mirroring elemHolder via CAPortalLayer)
    Class keyFillEffectClass = NSClassFromString(@"CASDFKeyFillHighlightEffect");
    Class portalClass = NSClassFromString(@"CAPortalLayer");
    if (keyFillEffectClass && portalClass) {
        CALayer *rimLayer = [[sdfLayerClass alloc] init];
        rimLayer.name = @"@2";
        rimLayer.frame = bounds;
        rimLayer.opacity = 0.65f;
        [rimLayer setValue:@8.0 forKey:@"smoothness"];
        [rimLayer setValue:@0.0 forKey:@"effectOffset"];
        [rimLayer setValue:@0.0 forKey:@"gaussianRadius"];
        [rimLayer setValue:@NO forKey:@"mergeElements"];

        NSObject *keyFill = [[keyFillEffectClass alloc] init];
        // Opposing top-left (135 deg) and bottom-right (-45 deg) crystalline catchlights
        [keyFill setValue:@(3.0 * M_PI_4) forKey:@"keyAngle"];
        [keyFill setValue:@(-M_PI_4) forKey:@"fillAngle"];
        [keyFill setValue:@1.0 forKey:@"keyHeight"];
        [keyFill setValue:@1.0 forKey:@"fillHeight"];
        [keyFill setValue:@1.0 forKey:@"keyHeightScale"];
        [keyFill setValue:@0.0 forKey:@"keyHeightOffset"];
        [keyFill setValue:@1.0 forKey:@"fillHeightScale"];
        [keyFill setValue:@0.0 forKey:@"fillHeightOffset"];
        [keyFill setValue:@1.396263401595464 forKey:@"keySpread"];
        [keyFill setValue:@1.396263401595464 forKey:@"fillSpread"];
        [keyFill setValue:@1.0 forKey:@"keySpreadScale"];
        [keyFill setValue:@0.0 forKey:@"keySpreadOffset"];
        [keyFill setValue:@1.0 forKey:@"fillSpreadScale"];
        [keyFill setValue:@0.0 forKey:@"fillSpreadOffset"];
        [keyFill setValue:@0.55 forKey:@"keyAmount"];
        [keyFill setValue:@0.42 forKey:@"fillAmount"];
        [keyFill setValue:@8.0 forKey:@"diffuseHeightScale"];
        [keyFill setValue:@0.15 forKey:@"diffuseAmountScale"];
        [keyFill setValue:@0.65 forKey:@"diffuseSpreadScale"];
        [keyFill setValue:@0.75 forKey:@"curvature"];
        [keyFill setValue:@NO forKey:@"global"];

        CGColorRef initKeyColor = CGColorCreateSRGB(1.0, 1.0, 1.0, 0.36);
        CGColorRef initFillColor = CGColorCreateSRGB(1.0, 1.0, 1.0, 0.24);
        [keyFill setValue:(__bridge id)initKeyColor forKey:@"keyColor"];
        [keyFill setValue:(__bridge id)initFillColor forKey:@"fillColor"];
        CGColorRelease(initKeyColor);
        CGColorRelease(initFillColor);

        [rimLayer setValue:keyFill forKey:@"effect"];

        // Apple's exact vibrantColorMatrix from macOS 27 NSGlassEffectView (@2)
        id vibrantFilter = DPMakeCAFilter(@"vibrantColorMatrix");
        if (vibrantFilter) {
            DPCAColorMatrix m = {
                 1.3192f, -0.0478f, -0.0047f, 0.0f, 0.2000f,
                -0.0142f,  1.2856f, -0.0048f, 0.0f, 0.2000f,
                -0.0142f, -0.0476f,  1.3285f, 0.0f, 0.2000f,
                 0.0000f,  0.0000f,  0.0000f, 1.0f, 0.0000f
            };
            NSValue *matrixVal = [NSValue valueWithBytes:&m objCType:"{CAColorMatrix=ffffffffffffffffffff}"];
            [vibrantFilter setValue:@"vibrantColorMatrix" forKey:@"name"];
            [vibrantFilter setValue:@YES forKey:@"inputClamp"];
            [vibrantFilter setValue:matrixVal forKey:@"inputColorMatrix"];
            rimLayer.filters = @[vibrantFilter];
        }

        CALayer *portal = [[portalClass alloc] init];
        portal.frame = CGRectZero;
        [portal setValue:elemHolder forKey:@"sourceLayer"];
        [portal setValue:@NO forKey:@"matchesPosition"];
        [portal setValue:@NO forKey:@"matchesTransform"];
        [portal setValue:@NO forKey:@"matchesOpacity"];
        [portal setValue:@NO forKey:@"hidesSourceLayer"];
        [rimLayer addSublayer:portal];

        [hostLayer addSublayer:rimLayer];
        _rimHighlightLayer = rimLayer;
        _rimHighlightEffect = keyFill;
    }

    _backdropLayer = backdrop;
    _sdfOutputLayer = sdfLayer;
    _sdfElementHolder = elemHolder;
    _sdfElementLayer = elem;

    return self;
}

- (void)updateLayoutForBounds:(CGRect)bounds cornerRadius:(CGFloat)cornerRadius {
    CGFloat minDim = MIN(bounds.size.width, bounds.size.height);
    if (minDim <= 0.0) {
        return;
    }
    CGFloat clampedRadius = MIN(cornerRadius, minDim * 0.5);

    self.backdropLayer.frame = bounds;
    self.sdfOutputLayer.frame = bounds;
    self.sdfElementLayer.frame = bounds;
    self.sdfElementLayer.cornerRadius = clampedRadius;
    self.rimHighlightLayer.frame = bounds;

    // Scale inner refraction & chromatic aberration proportionally to pill thickness (Apple's formula)
    double refractionAmount = -MIN(minDim * 0.62, 46.0);
    double refractionHeight = MIN(minDim * 0.30, 20.0);
    double aberrationHeight = MIN(minDim * 0.26, 18.0);

    [self.backdropLayer setValue:@(refractionAmount) forKeyPath:@"filters.glassBackground.inputInnerRefractionAmount"];
    [self.backdropLayer setValue:@(refractionHeight) forKeyPath:@"filters.glassBackground.inputInnerRefractionHeight"];
    [self.backdropLayer setValue:@(aberrationHeight) forKeyPath:@"filters.glassBackground.inputAberrationHeight"];
}

- (void)applyAppearanceParams:(DPLiquidGlassAppearanceParams)params {
    [self.backdropLayer setValue:@(params.blurRadius) forKeyPath:@"filters.glassBackground.inputBlurRadius"];
    [self.backdropLayer setValue:@(params.blurOpacity) forKeyPath:@"filters.glassBackground.inputBlurOpacity0"];
    [self.backdropLayer setValue:@(params.blurOpacity) forKeyPath:@"filters.glassBackground.inputBlurOpacity1"];
    [self.backdropLayer setValue:@(params.blurOpacity) forKeyPath:@"filters.glassBackground.inputBlurOpacity2"];
    [self.backdropLayer setValue:@(params.blurOpacity) forKeyPath:@"filters.glassBackground.inputBlurOpacity3"];
    [self.backdropLayer setValue:@(params.aberrationAmount) forKeyPath:@"filters.glassBackground.inputAberrationAmount"];
    [self.backdropLayer setValue:@(params.faceBlack) forKeyPath:@"filters.glassBackground.inputFaceColorMatrixBlack"];
    [self.backdropLayer setValue:@(params.faceWhite) forKeyPath:@"filters.glassBackground.inputFaceColorMatrixWhite"];
    [self.backdropLayer setValue:@(params.faceSaturation) forKeyPath:@"filters.glassBackground.inputFaceColorMatrixSaturation"];

    CGColorRef fillColor = CGColorCreateSRGB(params.faceFillRed, params.faceFillGreen, params.faceFillBlue, params.faceFillAlpha);
    [self.backdropLayer setValue:(__bridge id)fillColor forKeyPath:@"filters.glassBackground.inputFaceColorMatrixFillColor"];
    CGColorRelease(fillColor);

    [self.backdropLayer setValue:@(params.keyFillHighlightAmount) forKeyPath:@"filters.glassBackground.inputKeyFillHighlightAmount"];

    if (self.rimHighlightLayer && self.rimHighlightEffect) {
        self.rimHighlightLayer.opacity = (float)params.rimSpecularOpacity;
        CGColorRef keyColor = CGColorCreateSRGB(params.rimRed, params.rimGreen, params.rimBlue, params.rimKeyAlpha);
        CGColorRef fillRimColor = CGColorCreateSRGB(params.rimRed, params.rimGreen, params.rimBlue, params.rimFillAlpha);
        [self.rimHighlightEffect setValue:(__bridge id)keyColor forKey:@"keyColor"];
        [self.rimHighlightEffect setValue:(__bridge id)fillRimColor forKey:@"fillColor"];
        CGColorRelease(keyColor);
        CGColorRelease(fillRimColor);
        // Re-assign effect so Core Animation commits updated CGColor properties to the render server
        [self.rimHighlightLayer setValue:self.rimHighlightEffect forKey:@"effect"];
    }
}

@end
