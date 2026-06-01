#import "DDC.h"
#import <IOKit/IOKitLib.h>
#import <dlfcn.h>

typedef CFTypeRef IOAVServiceRef;
typedef IOAVServiceRef (*IOAVServiceCreateWithServiceFn)(CFAllocatorRef allocator, io_service_t service);
typedef IOReturn (*IOAVServiceWriteI2CFn)(IOAVServiceRef service, uint32_t chipAddress, uint32_t dataAddress,
                                          const void *inputBuffer, uint32_t inputBufferSize);
typedef IOReturn (*IOAVServiceReadI2CFn)(IOAVServiceRef service, uint32_t chipAddress, uint32_t offset,
                                         void *outputBuffer, uint32_t outputBufferSize);

static const uint32_t kDDCChipAddress = 0x37;
static const uint32_t kDDCDataRegister = 0x51;

@implementation DDC {
    IOAVServiceRef _avService;
    IOAVServiceWriteI2CFn _writeI2C;
    IOAVServiceReadI2CFn _readI2C;
    NSLock *_lock;
}

- (nullable instancetype)init {
    self = [super init];
    if (!self) return nil;

    void *handle = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_NOW);
    if (!handle) {
        fprintf(stderr, "ddcvol: failed to load CoreDisplay framework\n");
        return nil;
    }
    IOAVServiceCreateWithServiceFn create = dlsym(handle, "IOAVServiceCreateWithService");
    _writeI2C = dlsym(handle, "IOAVServiceWriteI2C");
    _readI2C = dlsym(handle, "IOAVServiceReadI2C");
    if (!create || !_writeI2C || !_readI2C) {
        fprintf(stderr, "ddcvol: failed to resolve IOAVService symbols\n");
        return nil;
    }

    // Find the external display's DCP AV service in the IO registry.
    io_iterator_t iterator;
    if (IOServiceGetMatchingServices(kIOMainPortDefault,
                                     IOServiceMatching("DCPAVServiceProxy"),
                                     &iterator) != KERN_SUCCESS) {
        return nil;
    }

    io_service_t service;
    while ((service = IOIteratorNext(iterator)) != MACH_PORT_NULL) {
        CFStringRef location = IORegistryEntryCreateCFProperty(service, CFSTR("Location"),
                                                               kCFAllocatorDefault, 0);
        BOOL isExternal = location && CFEqual(location, CFSTR("External"));
        if (location) CFRelease(location);

        if (isExternal) {
            _avService = create(kCFAllocatorDefault, service);
            IOObjectRelease(service);
            break;
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);

    if (!_avService) return nil;
    _lock = [[NSLock alloc] init];
    return self;
}

- (void)dealloc {
    if (_avService) CFRelease(_avService);
}

- (BOOL)write:(DDCVCPCode)code value:(uint16_t)value {
    [_lock lock];

    uint8_t packet[6] = {0x84, 0x03, code, (uint8_t)(value >> 8), (uint8_t)(value & 0xFF), 0};
    packet[5] = 0x6E ^ 0x51 ^ packet[0] ^ packet[1] ^ packet[2] ^ packet[3] ^ packet[4];

    BOOL success = NO;
    for (int attempt = 0; attempt < 4; attempt++) {
        if (attempt > 0) usleep(20000);
        if (_writeI2C(_avService, kDDCChipAddress, kDDCDataRegister, packet, sizeof(packet)) == KERN_SUCCESS) {
            success = YES;
            break;
        }
    }

    [_lock unlock];
    return success;
}

- (NSInteger)read:(DDCVCPCode)code {
    [_lock lock];

    uint8_t request[4] = {0x82, 0x01, code, 0};
    request[3] = 0x6E ^ 0x51 ^ request[0] ^ request[1] ^ request[2];

    NSInteger result = -1;
    for (int attempt = 0; attempt < 4; attempt++) {
        if (attempt > 0) usleep(40000);

        if (_writeI2C(_avService, kDDCChipAddress, kDDCDataRegister, request, sizeof(request)) != KERN_SUCCESS)
            continue;
        usleep(50000);

        uint8_t reply[11] = {0};
        if (_readI2C(_avService, kDDCChipAddress, kDDCDataRegister, reply, sizeof(reply)) != KERN_SUCCESS)
            continue;

        // Reply: [src, len, 0x02, result, vcp, type, maxHi, maxLo, curHi, curLo, checksum]
        if (reply[2] == 0x02 && reply[3] == 0x00 && reply[4] == code) {
            result = (reply[8] << 8) | reply[9];
            break;
        }
    }

    [_lock unlock];
    return result;
}

@end
