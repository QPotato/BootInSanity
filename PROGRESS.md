# BootInSanity — Progress

Branch: **trixie-xlibre** (Debian 13, kernel 6.12). Last updated: 2026-05-09.

## Current status

| Phase | Status | Notes |
|---|---|---|
| 0+1 Live + XSanity | ✅ Hardware validated | Sound, video, PIUIO, cabinet lights all working on MK9 |
| 2 Installer | ✅ Hardware validated | Clean + update flow both confirmed on MK9 (rc7) |
| 3 IO + PIUIO | ✅ | XSanity reads PIUIO natively via libusb; usbhid quirk confirmed working |
| 3c NVIDIA | 🟡 Opt-in, broken on trixie 6.12 | Upstream `.run` (470.256.02 + 535.247.01) staged via `make fetch-nvidia`; auto-detect via `nvidia-detect`; install at install-time gated by `install-nvidia` cmdline flag. 470 build fails on kernel ≥6.10 (`phys_to_dma`/`dma_is_direct` removed). Default = nouveau, which works for Kepler GT 710 on trixie. |
| 4 System mode | ✅ Hardware validated | Win+F4/G/S/V/B/P/R/M/X all wired; evdev watcher bypasses XGrabKeyboard |
| 5 Branding + docs | 🔴 Not started | |

## Hardware test results (rc3–rc7, installed mode, MK9)

| Item | Result |
|---|---|
| Boot to XSanity | ✅ |
| Video (nouveau, 720p) | ✅ — also confirmed on Kepler GT 710 (kernel 6.12, KMS, rc7) |
| Sound (ALC662) | ✅ Hum present at boot, stops after a few seconds (nocap fix in rc4, untested) |
| PIUIO panel input | ✅ XSanity reads PIUIO natively; usbhid quirk confirmed not claiming device |
| Cabinet lights | ✅ |
| Keyboard in XSanity | ✅ Fixed rc3 (evdev watcher was grabbing keyboards exclusively) |
| Win+F4 system mode | ✅ Terminal opens; XSanity window requires Alt+F4 to dismiss (cosmetic) |
| Win+V alsamixer | ✅ |
| Win+G return to game | Added rc5, untested on hardware |
| Win+S add songs | 🟡 Script reachable; USB auto-mount missing in kiosk session (manual mount required) |
| Installer YES input | ✅ Fixed rc3 |
| SSH via direct ethernet | ✅ Static IP 192.168.100.2 baked in from rc5 |
| Double pad input | ✅ Not present in installed mode (live mode only, low priority) |
| Update flow | ✅ Validated on MK9 in rc7 (preserved P3 across rootfs reflash) |

## Open issues

- **Win+F4 cosmetic**: XSanity process dies but window lingers until Alt+F4 — WM repaint issue, not a crash
- **Audio hum at boot**: capture ADC switch left on by default; `nocap` fix in rc4, needs hardware retest
- **NVIDIA proprietary on trixie**: 470.256.02 .run does not build against kernel 6.12 (`phys_to_dma` + `dma_is_direct` removed from kernel API). Default path is nouveau (works for Kepler GT 710). Proprietary install gated behind `install-nvidia` cmdline flag — currently fails for 470 branch until community patches are integrated. 535+ branch should still work for Maxwell-2.0+ but untested.
- **USB auto-mount**: Win+S `add-songs.sh` only finds drives auto-mounted under `/media/pump/*`. Kiosk session lacks udisks2 daemon → manual mount required. Next version: install + enable `udisks2`, or invoke `udisksctl mount` from the script.

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
make fetch-nvidia                    # one-time: cache NVIDIA .run files in vendor/nvidia/
make iso \
  DEBIAN_ISO=debian-13.x-amd64-DVD-1.iso \
  "XSANITY_DIR=XSanity 0.96.0/XSanity" \
  VERSION=v0.1-rc7
```

GPU driver auto-detected at install time (no `--gpu` flag). Default = nouveau / i915 / amdgpu KMS. Add `install-nvidia` to kernel cmdline to attempt NVIDIA proprietary install (currently broken on trixie 6.12 for 470 branch — see open issues).

Cached Docker build (~5 min). Fresh build (`NO_CACHE=1`) ~15 min. ISO ~1.8 G (depends on staged XSanity content size).
