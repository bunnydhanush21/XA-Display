# XA Display battery-care helper

Optional root helper for the experimental charge limit. It is not part of the iPad app or the Mac host. The app keeps working with telemetry only if this helper is absent.

This program is original MIT code. ChargeLimiter is GPL-3.0 and is a behavior reference only. None of its source is copied here.

## What it will and will not do

The helper accepts four commands on a local Unix socket: `status`, `charge-off`, `charge-on`, and `restore`. `charge-off` sets the power-source property `IsCharging` to false. `charge-on` and `restore` set it back to true. Those are the only registry writes.

It does not listen on the network, spawn a shell, or write `DisableInflow` or `ExternalConnected`. If telemetry goes stale, the helper also turns charging back on after 45 seconds without a command. SIGTERM does the same, so unloading the job restores charging.

## Entitlements

`entitlements.plist` requests `platform-application` and `com.apple.private.iokit.powersource`. Those private entitlements are what let a jailbreak-signed root process change `IsCharging` on iOS 12. A normal App Store signature cannot use them. Sign with `ldid`, not with an App Store profile:

```bash
xcrun -sdk iphoneos clang -arch arm64 -miphoneos-version-min=12.0 \
  -framework IOKit -framework CoreFoundation \
  -o XADisplayBatteryCare main.c
ldid -Sentitlements.plist XADisplayBatteryCare
```

The iPhoneOS SDK sometimes omits IOKit headers. Use a jailbreak toolchain that provides `IOKit/IOKitLib.h` if that command cannot find the headers. Do not copy headers out of a GPL project.

## Install

```bash
mkdir -p /var/mobile/Library/XADisplay
openssl rand -hex 16 > /var/mobile/Library/XADisplay/battery-care.token
chown root:mobile /var/mobile/Library/XADisplay/battery-care.token
chmod 0640 /var/mobile/Library/XADisplay/battery-care.token
cp XADisplayBatteryCare /usr/local/bin/XADisplayBatteryCare
cp com.bunnydhanush.xadisplay.batterycare.plist /Library/LaunchDaemons/
launchctl load /Library/LaunchDaemons/com.bunnydhanush.xadisplay.batterycare.plist
```

## Kill switch and uninstall

Creating this file makes `charge-off` restore charging instead:

```bash
touch /var/mobile/Library/XADisplay/battery-care.disabled
```

The iPad button **Disable battery care** writes that file. Remove the file only after you mean to arm the limit again.

Uninstall restores charging and removes the job:

```bash
launchctl unload /Library/LaunchDaemons/com.bunnydhanush.xadisplay.batterycare.plist
rm -f /usr/local/bin/XADisplayBatteryCare
rm -f /Library/LaunchDaemons/com.bunnydhanush.xadisplay.batterycare.plist
rm -f /var/run/xadisplay-battery.sock
```

Unload sends SIGTERM, and the helper sets `IsCharging` back to true before it exits.
