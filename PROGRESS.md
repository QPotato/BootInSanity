# BootInSanity — Progress

Branch: **trixie-xlibre** (Debian 13, kernel 6.x). Last updated: 2026-05-04.

## Current status

| Phase | Status | Notes |
|---|---|---|
| 0+1 Live + XSanity | ✅ Hardware validated | Sound, video, PIUIO, cabinet lights all working on MK9 |
| 2 Installer | ✅ QEMU validated | Clean install + update flow both working |
| 3 IO + pumptools | ✅ | PIUIO reads natively via XSanity; pumptools present for legacy PIU |
| 3c NVIDIA | 🔴 Not started | GPU=nouveau only; legacy driver packaging pending |
| 4 System mode | 🟡 Implemented | evdev hotkey watcher bypasses XGrabKeyboard; pending hardware retest |
| 5 Branding + docs | 🔴 Not started | |

## Hardware test results (v0.1-rc1, live mode, MK9)

| Item | Result |
|---|---|
| Boot to XSanity | ✅ |
| Video (nouveau, 720p) | ✅ |
| Sound (ALC662) | ✅ |
| PIUIO panel input | ✅ XSanity reads PIUIO natively |
| Cabinet lights | ✅ Working out of the box |
| Win+F4 system mode | ❌ XSanity grabs keyboard; evdev watcher added in rc2 |
| Audio background noise | 🟡 Low hum; ALSA capture mutes added in rc2 |
| Duplicate input | ❌ piuio2key was running alongside XSanity; removed in rc2 |

## Open issues

- **Win+F4 on hardware**: evdev watcher (`bootinsanity-hotkeys.service`) added in rc2 — untested on hardware
- **NVIDIA GPU**: nouveau is functional; GT710 and older cards need proprietary drivers for best performance
- **SSH access**: requires ethernet cable + manual IP assignment on both sides (no DHCP on direct link)

## Key decisions

- **PIUIO**: XSanity reads PIUIO directly via libusb. No kernel module or userspace bridge needed.
- **Audio**: ALSA only. PulseAudio/PipeWire masked. ALSA capture paths muted at boot to prevent loopback hum.
- **System mode hotkeys**: evdev-level watcher reads `/dev/input/*` directly — cannot be blocked by X11 grabs.
- **pumptools**: installed at `/opt/pumptools/` for legacy PIU game support. Hook map in `piu-launch.sh`.
- **Installer**: squashfs live-boot approach; installer triggered by `install=clean|update` kernel param. `install=update-yes` skips confirmation (used by `make qemu-update`).

## Disk layout

| Part | Size | Mount | Purpose |
|---|---|---|---|
| p1 | 256 MB | `/boot/efi` | ESP + BIOS MBR |
| p2 | 8 GB | `/` | System rootfs (re-flashed on update) |
| p3 | rest | `/mnt/xsanity` | XSanity + Songs + Save + Cache (preserved on update) |

XSanity is excluded from the p2 squashfs extraction and written directly to p3 during clean install.

## Build

```bash
make iso \
  DEBIAN_ISO=debian-13.x-amd64-DVD-1.iso \
  "XSANITY_DIR=XSanity 0.96.0/XSanity" \
  VERSION=v0.1-rc2 \
  GPU=nouveau
```

Cached Docker build (~5 min). Fresh build (`NO_CACHE=1`) ~15 min.
No kernel module compilation (removed — PIUIO is not HID; usbhid patch had no effect on gameplay input).
