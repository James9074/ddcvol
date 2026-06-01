#import <Foundation/Foundation.h>
#import "DDC.h"

extern const NSInteger kVolumeStep;

/// Daemon mode: capture the keyboard volume keys (volume up / down / mute) and
/// translate them into DDC volume commands for the external monitor.
///
/// Keys are only intercepted while the monitor (DisplayPort/HDMI) is the default
/// audio output — otherwise they pass through and behave normally.
@interface MediaKeyListener : NSObject

- (instancetype)initWithDDC:(DDC *)ddc;

/// Runs the event tap and app loop. Never returns.
- (void)run __attribute__((noreturn));

@end
