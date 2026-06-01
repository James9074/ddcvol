#import "Audio.h"
#import <CoreAudio/CoreAudio.h>

BOOL DefaultOutputIsDisplay(void) {
    AudioDeviceID deviceID = 0;
    UInt32 size = sizeof(deviceID);
    AudioObjectPropertyAddress address = {
        .mSelector = kAudioHardwarePropertyDefaultOutputDevice,
        .mScope = kAudioObjectPropertyScopeGlobal,
        .mElement = kAudioObjectPropertyElementMain,
    };
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, &deviceID) != noErr)
        return NO;

    UInt32 transport = 0;
    size = sizeof(transport);
    address.mSelector = kAudioDevicePropertyTransportType;
    if (AudioObjectGetPropertyData(deviceID, &address, 0, NULL, &size, &transport) != noErr)
        return NO;

    return transport == kAudioDeviceTransportTypeDisplayPort
        || transport == kAudioDeviceTransportTypeHDMI;
}
