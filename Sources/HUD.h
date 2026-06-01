#import <AppKit/AppKit.h>

/// A small translucent volume overlay, shown briefly when volume changes.
@interface VolumeHUD : NSObject

- (instancetype)init;
- (void)showVolume:(NSInteger)volume muted:(BOOL)muted;

@end
