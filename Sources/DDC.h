#import <Foundation/Foundation.h>

// VCP feature codes (MCCS standard)
typedef NS_ENUM(uint8_t, DDCVCPCode) {
    DDCVCPLuminance = 0x10,
    DDCVCPVolume    = 0x62,
    DDCVCPMute      = 0x8D,
};

/// DDC/CI control of an external display on Apple Silicon.
///
/// Talks to the monitor over the display cable's I2C channel using the private
/// IOAVService API in CoreDisplay.framework (same mechanism as m1ddc / MonitorControl).
@interface DDC : NSObject

/// Returns nil if no DDC-capable external display is found.
- (nullable instancetype)init;

/// Set a VCP feature value. Returns YES on success.
- (BOOL)write:(DDCVCPCode)code value:(uint16_t)value;

/// Read a VCP feature's current value. Returns -1 on failure.
- (NSInteger)read:(DDCVCPCode)code;

@end
