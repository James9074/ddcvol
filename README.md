# ddcvol

Control an external monitor's volume from your Mac's keyboard volume keys, over
DDC/CI — for Apple Silicon Macs whose audio output is an HDMI/DisplayPort monitor.

<p align="center">
<img width="300" height="102" alt="image" src="https://github.com/user-attachments/assets/9054ba80-d3e0-4cea-bac8-003d0db9c195" />
</p>

## Why

When macOS sends audio over DisplayPort/HDMI, the DAC lives in the monitor, so
macOS greys out the volume slider and the volume keys do nothing. Instead of
re-scaling audio in software (the SoundSource approach), `ddcvol` sends DDC/CI
commands over the display cable to change the monitor's *own* hardware volume —
bit-perfect audio, no virtual audio driver, no latency.

Uses the private `IOAVService` API in CoreDisplay.framework (the same mechanism
as [m1ddc](https://github.com/waydabber/m1ddc) and
[MonitorControl](https://github.com/MonitorControl/MonitorControl)).

## Build & install

```sh
make                # build ./ddcvol
make install        # install to ~/bin
make install-agent  # also start the volume-key daemon at login
make uninstall      # remove binary + agent
```

## Usage

```
ddcvol get             Print current monitor volume (0-100)
ddcvol set <0-100>     Set monitor volume
ddcvol up [step]       Increase volume (default step 5)
ddcvol down [step]     Decrease volume
ddcvol mute            Toggle mute (0 <-> previous volume)
ddcvol listen          Daemon: keyboard volume keys control the monitor
```

## The daemon (`ddcvol listen`)

Captures the keyboard volume up / down / mute keys and translates them into DDC
commands, with a small on-screen volume HUD and the system volume-change sound.

- Keys are intercepted **only while the default audio output is the
  DisplayPort/HDMI monitor** — switch to other speakers/headphones and the keys
  behave normally again.
- Requires **Accessibility** permission (System Settings → Privacy & Security →
  Accessibility → enable `ddcvol`). The daemon prompts for it on first run and
  waits until granted.
- Daemon log: `/tmp/ddcvol.log`

## Requirements

- Apple Silicon Mac
- A monitor that supports DDC/CI volume control (VCP code 0x62) — most do.
  If `ddcvol get` prints a number, you're good.
- macOS Command Line Tools (to build)

## Files

| File | Purpose |
|---|---|
| `Sources/DDC.{h,m}` | DDC/CI over IOAVService (I2C on the display cable) |
| `Sources/Audio.{h,m}` | Detects whether the default audio output is the monitor |
| `Sources/Listener.{h,m}` | Volume-key event tap + DDC write coalescing |
| `Sources/HUD.{h,m}` | Translucent on-screen volume overlay |
| `Sources/main.m` | CLI |
| `com.james.ddcvol.plist` | LaunchAgent template (started by `make install-agent`) |
