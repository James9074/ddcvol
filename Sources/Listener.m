#import "Listener.h"
#import "Audio.h"
#import "HUD.h"
#import <AppKit/AppKit.h>

const NSInteger kVolumeStep = 5;

// NX_KEYTYPE_* from IOKit/hidsystem/ev_keymap.h
static const NSInteger kKeySoundUp = 0;
static const NSInteger kKeySoundDown = 1;
static const NSInteger kKeyMute = 7;
static const CGEventType kNXSysdefined = 14; // NX_SYSDEFINED

@interface MediaKeyListener ()
- (CGEventRef)handleEventOfType:(CGEventType)type event:(CGEventRef)event;
@end

static CGEventRef EventTapCallback(CGEventTapProxy proxy, CGEventType type,
                                   CGEventRef event, void *refcon) {
    MediaKeyListener *listener = (__bridge MediaKeyListener *)refcon;
    return [listener handleEventOfType:type event:event];
}

@implementation MediaKeyListener {
    DDC *_ddc;
    VolumeHUD *_hud;
    CFMachPortRef _eventTap;
    dispatch_queue_t _ddcQueue;

    NSInteger _volume;          // 0-100, tracked locally (DDC reads are slow)
    BOOL _muted;
    NSInteger _lastUnmutedVolume;

    // Coalesce rapid key repeats into a single in-flight DDC write
    NSLock *_pendingLock;
    NSNumber *_pendingValue;
    BOOL _writeInFlight;

    NSSound *_feedbackSound;
}

- (instancetype)initWithDDC:(DDC *)ddc {
    self = [super init];
    if (!self) return nil;

    _ddc = ddc;
    _ddcQueue = dispatch_queue_create("ddcvol.ddc-write", DISPATCH_QUEUE_SERIAL);
    _pendingLock = [[NSLock alloc] init];

    NSInteger current = [ddc read:DDCVCPVolume];
    _volume = current >= 0 ? current : 50;
    _muted = (_volume == 0);
    _lastUnmutedVolume = _volume > 0 ? _volume : 50;

    // The sound macOS plays on volume change
    NSString *soundPath = @"/System/Library/LoudnessManager.framework/Versions/A/Resources/volume.aiff";
    if ([[NSFileManager defaultManager] fileExistsAtPath:soundPath]) {
        _feedbackSound = [[NSSound alloc] initWithContentsOfFile:soundPath byReference:YES];
    }

    return self;
}

- (void)run {
    // Need accessibility permission for the event tap
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
    if (!AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options)) {
        fprintf(stderr, "ddcvol: waiting for Accessibility permission "
                        "(System Settings > Privacy & Security > Accessibility)...\n");
        while (!AXIsProcessTrusted()) sleep(2);
        fprintf(stderr, "ddcvol: permission granted\n");
    }

    NSApplication *app = [NSApplication sharedApplication];
    [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
    _hud = [[VolumeHUD alloc] init];

    CGEventMask mask = CGEventMaskBit(kNXSysdefined);
    _eventTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap,
                                 kCGEventTapOptionDefault, mask,
                                 EventTapCallback, (__bridge void *)self);
    if (!_eventTap) {
        fprintf(stderr, "ddcvol: failed to create event tap (is Accessibility permission granted?)\n");
        exit(4);
    }

    CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, _eventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
    CFRelease(source);
    CGEventTapEnable(_eventTap, true);

    fprintf(stderr, "ddcvol: listening for volume keys (monitor volume: %ld)\n", (long)_volume);
    [app run];
    exit(0);
}

- (CGEventRef)handleEventOfType:(CGEventType)type event:(CGEventRef)event {
    // Re-enable the tap if the system disabled it (timeout / user input)
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        if (_eventTap) CGEventTapEnable(_eventTap, true);
        return event;
    }

    if (type != kNXSysdefined) return event;

    NSEvent *nsEvent = [NSEvent eventWithCGEvent:event];
    if (!nsEvent || nsEvent.subtype != 8 /* NX_SUBTYPE_AUX_CONTROL_BUTTONS */) return event;

    NSInteger data1 = nsEvent.data1;
    NSInteger keyCode = (data1 & 0xFFFF0000) >> 16;
    NSInteger keyFlags = data1 & 0x0000FFFF;
    BOOL keyDown = ((keyFlags & 0xFF00) >> 8) == 0x0A;

    if (keyCode != kKeySoundUp && keyCode != kKeySoundDown && keyCode != kKeyMute)
        return event;

    // Only take over when audio is actually going to the monitor
    if (!DefaultOutputIsDisplay())
        return event;

    if (keyDown) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handleKey:keyCode];
        });
    }
    // Consume both key-down and key-up so macOS doesn't show its own
    // (non-functional) volume bezel.
    return NULL;
}

- (void)handleKey:(NSInteger)keyCode {
    if (keyCode == kKeySoundUp) {
        if (_muted) { _muted = NO; _volume = _lastUnmutedVolume; }
        _volume = MIN(100, _volume + kVolumeStep);
    } else if (keyCode == kKeySoundDown) {
        if (_muted) { _muted = NO; _volume = _lastUnmutedVolume; }
        _volume = MAX(0, _volume - kVolumeStep);
    } else if (keyCode == kKeyMute) {
        if (_muted) {
            _muted = NO;
            _volume = _lastUnmutedVolume;
        } else {
            if (_volume > 0) _lastUnmutedVolume = _volume;
            _muted = YES;
            _volume = 0;
        }
    } else {
        return;
    }

    [_hud showVolume:_volume muted:_muted];
    [_feedbackSound stop];
    [_feedbackSound play];
    [self pushVolume:_volume];
}

/// Send the new volume to the monitor, coalescing rapid changes so DDC
/// writes never back up behind key-repeat.
- (void)pushVolume:(NSInteger)value {
    [_pendingLock lock];
    _pendingValue = @(value);
    if (_writeInFlight) {
        [_pendingLock unlock];
        return;
    }
    _writeInFlight = YES;
    [_pendingLock unlock];

    dispatch_async(_ddcQueue, ^{
        while (true) {
            [self->_pendingLock lock];
            NSNumber *next = self->_pendingValue;
            self->_pendingValue = nil;
            if (!next) {
                self->_writeInFlight = NO;
                [self->_pendingLock unlock];
                return;
            }
            [self->_pendingLock unlock];

            uint16_t target = (uint16_t)next.integerValue;
            if (![self->_ddc write:DDCVCPVolume value:target]) {
                // Display may have been re-plugged; try to reconnect once
                DDC *fresh = [[DDC alloc] init];
                if (fresh) {
                    self->_ddc = fresh;
                    [self->_ddc write:DDCVCPVolume value:target];
                }
            }
        }
    });
}

@end
