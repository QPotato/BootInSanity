# BootInSanity — Progress

Branch: **trixie-xlibre** (Debian 13, kernel 6.x). Last updated: 2026-05-05.

## Current status

| Phase | Status | Notes |
|---|---|---|
| 0+1 Live + XSanity | ✅ Hardware validated | Sound, video, PIUIO, cabinet lights all working on MK9 |
| 2 Installer | ✅ Hardware validated | Clean install confirmed on MK9 (rc3+); update flow pending hardware test |
| 3 IO + PIUIO | ✅ | XSanity reads PIUIO natively via libusb; usbhid quirk confirmed working |
| 3c NVIDIA | 🔴 Not started | GPU=nouveau only; legacy driver packaging pending |
| 4 System mode | ✅ Hardware validated | Win+F4/G/S/V/B/P/R/M/X all wired; evdev watcher bypasses XGrabKeyboard |
| 5 Branding + docs | 🔴 Not started | |

## Hardware test results (rc3–rc5, installed mode, MK9)

| Item | Result |
|---|---|
| Boot to XSanity | ✅ |
| Video (nouveau, 720p) | ✅ |
| Sound (ALC662) | ✅ Hum present at boot, stops after a few seconds (nocap fix in rc4, untested) |
| PIUIO panel input | ✅ XSanity reads PIUIO natively; usbhid quirk confirmed not claiming device |
| Cabinet lights | ✅ |
| Keyboard in XSanity | ✅ Fixed rc3 (evdev watcher was grabbing keyboards exclusively) |
| Win+F4 system mode | ✅ Terminal opens; XSanity window requires Alt+F4 to dismiss (cosmetic) |
| Win+V alsamixer | ✅ |
| Win+G return to game | Added rc5, untested on hardware |
| Win+S add songs | Added rc5, untested on hardware |
| Installer YES input | ✅ Fixed rc3 |
| SSH via direct ethernet | ✅ Static IP 192.168.100.2 baked in from rc5 |
| Double pad input | ✅ Not present in installed mode (live mode only, low priority) |
| Update flow | 🟡 QEMU validated; hardware test pending |

## Open issues

- **Win+F4 cosmetic**: XSanity process dies but window lingers until Alt+F4 — WM repaint issue, not a crash
- **Audio hum at boot**: capture ADC switch left on by default; `nocap` fix in rc4, needs hardware retest
- **NVIDIA GPU**: nouveau functional; GT710 and older cards need proprietary drivers for best performance
- **Update flow**: not yet tested on hardware

## Key decisions

- **PIUIO**: XSanity reads PIUIO directly via libusb. No kernel module or userspace bridge needed. Confirmed via `/sys/bus/usb/drivers/usbhid/` — PIUIO not bound.
- **Audio**: ALSA only. PulseAudio/PipeWire masked. Capture paths muted at boot.
- **System mode hotkeys**: evdev-level watcher reads `/dev/input/*` directly — cannot be blocked by X11 grabs. Does NOT grab devices (keyboards pass through to XSanity normally).
- **Installer**: squashfs live-boot approach; installer triggered by `install=clean|update` kernel param.
- **Songs**: on p3 (`/mnt/xsanity/Songs/`), preserved across updates. Win+S copies from USB.

## Disk layout

| Part | Size | Mount | Purpose |
|---|---|---|---|
| p1 | 256 MB | `/boot/efi` | ESP + BIOS MBR |
| p2 | 8 GB | `/` | System rootfs (re-flashed on update) |
| p3 | rest | `/mnt/xsanity` | XSanity + Songs + Save + Cache (preserved on update) |

## Build

```bash
make iso \
  DEBIAN_ISO=debian-13.x-amd64-DVD-1.iso \
  "XSANITY_DIR=XSanity 0.96.0/XSanity" \
  VERSION=v0.1-rc5 \
  GPU=nouveau
```

Cached Docker build (~5 min). Fresh build (`NO_CACHE=1`) ~15 min. ISO ~9.8G.
