#import "HUD.h"

static const CGFloat kPanelWidth = 240;
static const CGFloat kPanelHeight = 56;
static const CGFloat kBarWidth = 160;
static const CGFloat kBarHeight = 8;

@implementation VolumeHUD {
    NSPanel *_panel;
    NSImageView *_icon;
    NSView *_barFill;
    NSInteger _generation; // invalidates pending hide animations
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;

    _panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, kPanelWidth, kPanelHeight)
                                        styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
    _panel.level = NSScreenSaverWindowLevel;
    _panel.opaque = NO;
    _panel.backgroundColor = [NSColor clearColor];
    _panel.hasShadow = YES;
    _panel.ignoresMouseEvents = YES;
    _panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
                              | NSWindowCollectionBehaviorStationary
                              | NSWindowCollectionBehaviorFullScreenAuxiliary;

    NSVisualEffectView *effect = [[NSVisualEffectView alloc]
        initWithFrame:NSMakeRect(0, 0, kPanelWidth, kPanelHeight)];
    effect.material = NSVisualEffectMaterialHUDWindow;
    effect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    effect.state = NSVisualEffectStateActive;
    effect.wantsLayer = YES;
    effect.layer.cornerRadius = 14;
    effect.layer.masksToBounds = YES;
    _panel.contentView = effect;

    _icon = [[NSImageView alloc] initWithFrame:NSMakeRect(18, (kPanelHeight - 28) / 2, 28, 28)];
    _icon.imageScaling = NSImageScaleProportionallyUpOrDown;
    _icon.contentTintColor = [NSColor labelColor];
    [effect addSubview:_icon];

    NSView *barBackground = [[NSView alloc]
        initWithFrame:NSMakeRect(60, (kPanelHeight - kBarHeight) / 2, kBarWidth, kBarHeight)];
    barBackground.wantsLayer = YES;
    barBackground.layer.backgroundColor = [NSColor tertiaryLabelColor].CGColor;
    barBackground.layer.cornerRadius = kBarHeight / 2;
    [effect addSubview:barBackground];

    _barFill = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 0, kBarHeight)];
    _barFill.wantsLayer = YES;
    _barFill.layer.backgroundColor = [NSColor labelColor].CGColor;
    _barFill.layer.cornerRadius = kBarHeight / 2;
    [barBackground addSubview:_barFill];

    return self;
}

- (void)showVolume:(NSInteger)volume muted:(BOOL)muted {
    NSString *symbolName;
    if (muted || volume == 0) {
        symbolName = @"speaker.slash.fill";
    } else if (volume < 34) {
        symbolName = @"speaker.wave.1.fill";
    } else if (volume < 67) {
        symbolName = @"speaker.wave.2.fill";
    } else {
        symbolName = @"speaker.wave.3.fill";
    }
    _icon.image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil];

    CGFloat fraction = muted ? 0 : (CGFloat)volume / 100.0;
    _barFill.frame = NSMakeRect(0, 0, kBarWidth * fraction, kBarHeight);

    // Bottom-center of the main screen
    NSScreen *screen = [NSScreen mainScreen];
    if (screen) {
        NSRect frame = screen.visibleFrame;
        [_panel setFrameOrigin:NSMakePoint(NSMidX(frame) - kPanelWidth / 2, NSMinY(frame) + 80)];
    }

    _panel.alphaValue = 1;
    [_panel orderFrontRegardless];

    // Hide after 1.5s unless another change comes in
    NSInteger generation = ++_generation;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        typeof(self) self = weakSelf;
        if (!self || self->_generation != generation) return;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = 0.4;
            self->_panel.animator.alphaValue = 0;
        } completionHandler:^{
            if (self->_generation == generation) [self->_panel orderOut:nil];
        }];
    });
}

@end
