#import <Foundation/Foundation.h>
#import "DDC.h"
#import "Listener.h"

// ddcvol — control an external monitor's volume over DDC/CI on Apple Silicon Macs.
//
// Why: when audio goes out over DisplayPort/HDMI, macOS can't adjust the volume
// (the DAC is in the monitor). This tool sends DDC/CI commands over the display
// cable to change the monitor's own hardware volume — and in `listen` mode binds
// it to the Mac's keyboard volume keys.

static void usage(void) __attribute__((noreturn));
static void usage(void) {
    printf("ddcvol — monitor volume control over DDC/CI\n"
           "\n"
           "Usage:\n"
           "  ddcvol get             Print current monitor volume (0-100)\n"
           "  ddcvol set <0-100>     Set monitor volume\n"
           "  ddcvol up [step]       Increase volume (default step %ld)\n"
           "  ddcvol down [step]     Decrease volume\n"
           "  ddcvol mute            Toggle mute (0 <-> previous volume)\n"
           "  ddcvol listen          Daemon: keyboard volume keys control the monitor\n",
           (long)kVolumeStep);
    exit(1);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) usage();
        NSString *command = @(argv[1]);

        // In listen mode (typically launched at login) the display may not be ready yet.
        if ([command isEqualToString:@"listen"]) {
            DDC *ddc = [[DDC alloc] init];
            BOOL warned = NO;
            while (!ddc) {
                if (!warned) {
                    fprintf(stderr, "ddcvol: no DDC-capable external display found, retrying...\n");
                    warned = YES;
                }
                sleep(5);
                ddc = [[DDC alloc] init];
            }
            MediaKeyListener *listener = [[MediaKeyListener alloc] initWithDDC:ddc];
            [listener run];
        }

        DDC *ddc = [[DDC alloc] init];
        if (!ddc) {
            fprintf(stderr, "ddcvol: no DDC-capable external display found\n");
            return 2;
        }

        if ([command isEqualToString:@"get"]) {
            NSInteger current = [ddc read:DDCVCPVolume];
            if (current < 0) {
                fprintf(stderr, "ddcvol: DDC read failed\n");
                return 3;
            }
            printf("%ld\n", (long)current);

        } else if ([command isEqualToString:@"set"]) {
            if (argc < 3) usage();
            NSInteger value = atoi(argv[2]);
            if (value < 0 || value > 100) usage();
            if (![ddc write:DDCVCPVolume value:(uint16_t)value]) {
                fprintf(stderr, "ddcvol: DDC write failed\n");
                return 3;
            }

        } else if ([command isEqualToString:@"up"] || [command isEqualToString:@"down"]) {
            NSInteger step = argc >= 3 ? atoi(argv[2]) : kVolumeStep;
            if (step <= 0) step = kVolumeStep;
            NSInteger current = [ddc read:DDCVCPVolume];
            if (current < 0) {
                fprintf(stderr, "ddcvol: DDC read failed\n");
                return 3;
            }
            NSInteger newValue = [command isEqualToString:@"up"]
                ? MIN(100, current + step)
                : MAX(0, current - step);
            if (![ddc write:DDCVCPVolume value:(uint16_t)newValue]) {
                fprintf(stderr, "ddcvol: DDC write failed\n");
                return 3;
            }
            printf("%ld\n", (long)newValue);

        } else if ([command isEqualToString:@"mute"]) {
            NSString *stateFile = [NSHomeDirectory() stringByAppendingPathComponent:@".ddcvol_premute"];
            NSInteger current = [ddc read:DDCVCPVolume];
            if (current < 0) {
                fprintf(stderr, "ddcvol: DDC read failed\n");
                return 3;
            }
            if (current > 0) {
                [[NSString stringWithFormat:@"%ld", (long)current]
                    writeToFile:stateFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
                [ddc write:DDCVCPVolume value:0];
                printf("muted\n");
            } else {
                NSString *saved = [NSString stringWithContentsOfFile:stateFile
                                                            encoding:NSUTF8StringEncoding error:nil];
                NSInteger restore = saved ? atoi(saved.UTF8String) : 50;
                if (restore <= 0 || restore > 100) restore = 50;
                [ddc write:DDCVCPVolume value:(uint16_t)restore];
                printf("unmuted (%ld)\n", (long)restore);
            }

        } else {
            usage();
        }
    }
    return 0;
}
