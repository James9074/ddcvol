#import <Foundation/Foundation.h>

/// True if the current default output device sends audio over the display
/// cable (DisplayPort or HDMI) — i.e. volume keys should control the monitor.
BOOL DefaultOutputIsDisplay(void);
