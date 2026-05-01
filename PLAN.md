# BootInSanity — Implementation Plan

A dedicated Linux live-installer image for running the XSanity Pump It Up
simulator on Andamiro MK9 hardware, modeled after the ITG (In The Groove)
system image but built on Debian 11 LTS.

## Goals

- Turn-key boot-and-play experience on MK9v1 / MK9v2 hardware at 720p60.
- Read-only system rootfs; user data (XSanity, Songs, Save, Cache) on writable
  partition that survives system updates.
- No GPU swap required: ship official NVIDIA legacy driver coverage for every
  stock MK9 GPU (8400GS, 9300GS, GT210, GT610, GT710).
- ITG-parity UX: auto-login, autostart, crash-loop relaunch, system-mode
  escape hatch, SSH-based song updates.
- Distributable as source on GitHub: no third-party binaries committed, no
  large-artifact hosting required.

## Target Hardware

Andamiro MK9 (Pump It Up cabinet, ~2014–2019).

| Component | MK9v1 | MK9v2 |
|---|---|---|
| Socket | LGA775 | LGA775 |
| CPU | Celeron E3400 → Core 2 Quad Q9650 / Xeon X3370 | Core 2 (DDR3 boards) |
| RAM | 4 GB DDR2 | 8 GB DDR3 |
| Motherboard | Gigabyte GA-945GCM-S2L / GA-945GZM-S2 | ASRock G41M-S3 / G41C-GS |
| GPU (stock) | GeForce 8400GS | 9300GS / GT210 / GT610 / GT710 |
| Display | HDMI/DVI/VGA, 31 kHz, 720p HD | same |
| I/O board | PIUIO universal; LXIO on LX cabs (~2017+) | same |

15 kHz CRT not supported in MVP (HD-only).

## XSanity Runtime Notes

- ELF x86_64. Bundles 93 vendored shared objects in `lib/`.
- Launcher `XSanity.sh` runs binary via bundled `ld-linux-x86-64.so.2` with
  `LD_LIBRARY_PATH=lib/`. Host glibc version irrelevant to XSanity itself
  (newer bundled libc forward-compatible with older system libs).
- License: "free usage only" (non-OSI). User supplies XSanity, project never
  redistributes.
- Audio: backend selected at runtime via `Preferences.ini` (`SoundDevice=ALSA-SW`).

## Distro Decision

**Debian 11 (bullseye), LTS**.

| Distro | nv-340 | nv-390 | nv-470 | EOL | Glibc |
|---|---|---|---|---|---|
| Ubuntu 24.04 LTS | ✗ | ✗ | ✓ | 2029 | 2.39 |
| Ubuntu 22.04 LTS | ✗ | ✓ | ✓ | 2027 | 2.35 |
| **Debian 11 LTS** | **✓** | **✓** | **✓** | **2026-08** | **2.31** |
| Debian 12 | ✗ | ✓ | ✓ | 2028 | 2.36 |

Bullseye is the only LTS shipping all three legacy drivers as official
packages. EOL 2026-08; migration to bookworm planned post-MVP if 8400GS
falls below relevance threshold.

## User-Facing Workflow

```
[user-local Linux machine]
  user has: debian-11.x-amd64-DVD-1.iso  +  XSanity-0.96.0/ folder

  $ ./build.sh \
      --debian-iso ~/Downloads/debian-11.iso \
      --xsanity-dir ~/Downloads/XSanity \
      --output bootinsanity-v0.1-installer.iso

  → bootinsanity-v0.1-installer.iso  (Clonezilla-style live installer)

[install medium]
  user dd's ISO → USB stick (or drops on Ventoy USB alongside other media)

[target MK9]
  boot USB → "Clean Install" → wipes target disk → writes 3 partitions
    p1 boot, p2 rootfs (XSanity baked in via post-install extraction),
    p3 fills remaining disk
  reboot → auto-login pump:pump → X11 + i3 → XSanity launches → playable

[later — songs management]
  user $ scp -r Songs/ pump@<mk9-ip>:/mnt/xsanity/Songs/
  reboot → cache regen on first launch → play
```

Key properties:

- No XSanity, no Debian, no large blobs in repo.
- Build runs locally on user's Linux host (Docker-wrapped for reproducibility).
- Air-gap-friendly: full Debian DVD ISO + local XSanity = zero network during build.
- "Tested combinations" matrix in README documents verified Debian-ISO ×
  XSanity-version pairs.

## Disk Layout (Installed System)

3 partitions, msdos partition table, hybrid BIOS+UEFI.

| Part | Size | FS | Mount | Mode | Purpose |
|---|---|---|---|---|---|
| p1 | 256 MB | vfat | `/boot/efi` | ro | ESP + legacy boot |
| p2 | 8 GB | ext4 | `/` | ro (remount rw on demand) | rootfs (system) |
| p3 | rest | ext4 | `/mnt/xsanity` | rw | XSanity binary + Songs + SongMovies + Save + Cache |

Update flow re-flashes only p2; p3 preserved across system updates.

## Repository Layout

```
bootinsanity/
├── README.md                  # quickstart, tested combos
├── LICENSE                    # MIT (build scripts only)
├── Dockerfile                 # debian:bullseye + build deps
├── Makefile                   # make iso / make qemu / make clean
├── build.sh                   # entrypoint (CLI flags + interactive)
├── lib/
│   ├── extract-debian.sh      # mount ISO, set up apt source
│   ├── chroot-build.sh        # mmdebstrap + package install
│   ├── customize.sh           # apply overlay, configure services
│   ├── nvidia.sh              # install legacy 340 + 390 + 470
│   ├── kernel.sh              # patch + rebuild usbhid 1ms kmod
│   └── installer-iso.sh       # wrap rootfs into Clonezilla live ISO
├── overlay/                   # files copied into rootfs
│   ├── etc/
│   │   ├── systemd/system/getty@tty1.service.d/autologin.conf
│   │   ├── X11/xorg.conf.d/
│   │   ├── udev/rules.d/99-piuio.rules
│   │   ├── udev/rules.d/99-lxio.rules
│   │   ├── modprobe.d/blacklist-nvidia.conf
│   │   └── bootinsanity-version
│   ├── opt/bootinsanity/
│   │   ├── launch.sh          # XSanity crash-loop
│   │   ├── missing-xsanity.sh # full-screen "install XSanity" notice
│   │   ├── nvidia-pick.sh     # PCI ID → driver select on first boot
│   │   ├── firstboot.sh       # resize p3, extract XSanity, generate UUIDs
│   │   └── system-mode/       # Win+key utility scripts
│   └── home/pump/
│       ├── .xinitrc
│       ├── .bash_profile
│       └── .config/i3/config
├── kernel/
│   ├── usbhid-1ms.patch       # ported from ITG image
│   └── build-kmod.sh
├── installer/                 # Clonezilla customization
│   ├── isolinux.cfg           # boot menu (Clean Install / Update)
│   ├── grub.cfg               # EFI boot menu
│   ├── ocs-live-run.d/01-bootinsanity-firstrun
│   ├── theme/                 # grub + plymouth branding
│   └── postinstall.sh         # extract XSanity tarball to p3
├── docs/
│   ├── manual.md              # user-facing (mirrors ITG manual)
│   ├── hacking.md             # dev/build internals
│   └── tested-hw.md           # MK9 v1/v2 + GPU compat matrix
├── qemu/
│   ├── run-installer.sh       # boot installer ISO in QEMU
│   ├── run-installed.sh       # boot installed qcow2
│   └── usb-passthrough.sh     # attach real keyboard / PIUIO
└── tests/
    └── smoke.sh               # headless boot-to-XSanity check
```

## Build Pipeline (`build.sh`)

CLI:

```
Usage: ./build.sh [OPTIONS]

Required (interactive prompt if absent):
  --debian-iso PATH       full DVD ISO (debian-11.x-amd64-DVD-1.iso)
  --xsanity-dir PATH      folder containing XSanity binary + lib/ + assets
  --output PATH           output installer ISO

Optional:
  --no-cache              rebuild chroot from scratch
  --debug                 drop into chroot shell before ISO-pack
  --version STRING        version string baked into image (default: git describe)
```

Both CLI flags and interactive prompts supported (TTY-detect; flags override).

Steps:

1. Validate inputs: ISO is bullseye DVD, XSanity dir contains expected files.
2. Mount Debian ISO loop. Configure local apt source pointing at `/dists/`.
3. `mmdebstrap bullseye → /work/chroot` minimal base.
4. chroot install:
   - `linux-image-amd64` (5.10), `firmware-linux-nonfree`
   - `xserver-xorg-core`, `xinit`, `i3`, `xdotool`, `wmctrl`
   - `alsa-utils`, `evtest`, `pcmanfm`, `lxterminal`
   - `openssh-server`, `chrony`, `network-manager`
   - `parted`, `rsync`, `partclone`
   - `nvidia-legacy-340xx-driver`, `nvidia-legacy-390xx-driver`, `nvidia-driver`
5. Mask `pulseaudio`, `pipewire`, `pipewire-pulse`, `wireplumber`. ALSA only.
6. Apply `overlay/` rootfs.
7. Create `pump:pump` user, configure auto-login on tty1 → `startx`.
8. Build usbhid 1 ms patched kmod against installed kernel; install to chroot.
9. Configure SSH (port 22, password auth, `pump:pump` default — documented as
   credential to change in production).
10. partclone p2 rootfs → `installer/p2-rootfs.gz`.
11. Tar XSanity dir → `installer/xsanity.tar.zst` (deployed to p3 at install time).
12. Build Clonezilla-derived live ISO with `xorriso`:
    - live system from chroot
    - bundled p2 partclone + xsanity tarball
    - first-run scripts in `ocs-live-run.d/`
    - hybrid BIOS+EFI boot
13. Output: `bootinsanity-vX.Y-installer.iso`. Print SHA256.

## Installer Flow (Clonezilla-derived, on Target Disk)

1. Boot live ISO from USB.
2. Menu: **Clean Install** | **Update**.
3. **Clean Install**:
   - Detect target disk; prompt confirm wipe (destructive op gate).
   - `parted` writes 3 partitions. p1=256M vfat, p2=8G ext4, p3=rest ext4.
   - `partclone.restore` p2 from bundled image.
   - mkfs.ext4 p3, mount, extract `xsanity.tar.zst` → `/mnt/xsanity/`.
   - Symlink `/mnt/xsanity/Save` → `/mnt/xsanity/Save` (already on p3).
   - Generate fresh UUIDs in fstab and grub.cfg.
   - Install grub (BIOS) + grub-efi (EFI) on disk.
   - Reboot.
4. **Update**:
   - Re-flash p2 only. p3 untouched (preserves XSanity, Songs, Save, Cache).
   - Reboot.

## Boot UX (Installed System)

- GRUB → kernel → systemd.
- `getty@tty1` auto-logs in `pump`.
- `~/.bash_profile` exec's `startx`.
- `~/.xinitrc` starts `i3`.
- `i3` autostart runs `/opt/bootinsanity/launch.sh`:

```bash
#!/bin/bash
set -u
XSANITY=/mnt/xsanity/XSanity.sh

if [[ ! -x "$XSANITY" ]]; then
    exec /opt/bootinsanity/missing-xsanity.sh
fi

while :; do
    "$XSANITY"
    sleep 1
done
```

XSanity always launches on boot; relaunches automatically after exit/crash.
Power-off via cabinet switch is safe (rootfs ro, p3 mounted with `commit=1`
or sync writes for save data).

## System Mode (post-MVP, Phase 4)

ITG-parity escape hatch.

- **Caps Lock + Alt+F4** → kills XSanity, stops crash-loop, drops to `pcmanfm`
  + `lxterminal` desktop on i3.
- Win+key shortcuts (i3 keybinds):

| Key | Action |
|---|---|
| Win+M | Configure memory cards |
| Win+R | Reset XSanity settings |
| Win+P | Power off |
| Win+B | Reboot |
| Win+V | Volume mixer (`alsamixer`) |
| Win+E | Polling rate check (`evhz`) |
| Win+X | Expand p3 to end of disk |
| Win+Enter | System shell |

## QEMU Validation

`qemu/run-installer.sh`:

```bash
qemu-system-x86_64 \
  -enable-kvm -m 4G -smp 2 \
  -cdrom bootinsanity-vX.Y-installer.iso \
  -hda /tmp/target.qcow2 \
  -vga std -display gtk \
  -device usb-host,vendorid=0x...,productid=0x...   # PIUIO/keyboard
```

Two-stage:

1. Boot installer ISO → install to `target.qcow2`.
2. Boot from `target.qcow2` → verify XSanity launches at 720p60, audio out,
   keyboard input, SSH reachable.

`tests/smoke.sh`: headless QEMU boot, screenshot grab, OCR-check for
"Stepmania-loaded" or window-title match.

Real-hardware validation on user's MK9 follows QEMU green light.

## Distribution

- GitHub repo: build scripts + Dockerfile + docs only.
- No release artifacts hosted (user builds locally).
- Releases tagged with semver; release notes include tested-combination matrix
  and SHA256 of installer ISO produced from canonical inputs.
- No CI artifact pipeline. Optional GitHub Action for `shellcheck` + `make
  iso` smoke test (no upload).

## Trademark / Legal

- BootInSanity branding only — no Debian wordmark, no Canonical references, no
  "Ubuntu" anything.
- Custom GRUB theme + Plymouth splash + i3 wallpaper.
- Debian package licenses respected (apt source pointers in image; standard
  Debian behavior).
- XSanity supplied by user; never redistributed.

## Phases

| Phase | Scope | Output |
|---|---|---|
| **0** | Dockerfile + Makefile + skeleton `build.sh` | bare bullseye live ISO bootable in QEMU |
| **1 (MVP)** | Customize chroot, overlay X11+i3+ALSA+autologin, inject XSanity | live ISO that boots straight to XSanity in QEMU at 720p; audio + keyboard verified |
| **2** | Clonezilla-style installer wrapper, 3-partition install, first-boot resize | full install→reboot→play cycle in QEMU |
| **3** | NVIDIA legacy auto-pick, usbhid 1ms patch, PIUIO/LXIO udev | validated on real MK9 |
| **4** | System mode: Win+key shortcuts, status bar, file-manager escape | ITG-parity operator UX |
| **5** | Update flow (re-flash p2 only), branding polish, user manual | v1.0 release candidate |
| **6** | post-MVP: Saninet, lighting board picker, polling util (evhz), 15 kHz support | v1.x feature releases |

## Open Risks

- **8400GS + nvidia-340 on kernel 5.10**: driver builds against older kernels;
  bullseye's 5.10 is the upper edge of 340 compat. Validate early in Phase 3.
- **PIUIO/LXIO on bullseye 5.10**: udev rules + libusb access. Port from ITG
  image (Arch + linux-zen 5.10.11 — same kernel major). Should transfer
  cleanly.
- **usbhid 1 ms patch**: kernel ABI for usbhid changed across versions. ITG's
  patch targets 5.10.11; bullseye runs 5.10.x — same series, low risk.
- **bullseye EOL 2026-08**: ~16 months of LTS runway. Plan migration to
  bookworm before EOL; will require dropping nvidia-340 (8400GS → nouveau or
  GPU swap).
- **XSanity bundled glibc 2.42 vs Debian 11 system libs (glibc 2.31)**:
  forward-compat path not 100% covered; smoke-test early. Fallback: extract
  XSanity's bundled glibc symbols mapping or instruct user to source the
  pre-Linux-Mint-24.04 build of XSanity if bundled-loader strategy fails.

## Future Strategy — Trixie + Xlibre + Community NV Drivers (post-RC1)

### Context

Debian 11 (bullseye) reaches EOL 2026-08 (~16 months from now). MVP ships on bullseye;
post-RC1 pivot targets **Debian 13 (trixie)** + **Xlibre** (community StepMania variant)
to extend hardware support beyond EOL window and reduce maintainer burden.

### Trixie + Xlibre Foundation

| Item | Bullseye (current) | Trixie (future) |
|---|---|---|
| **Base Distro** | Debian 11 LTS, 5.10 kernel | Debian 13 LTS, 6.x kernel |
| **Simulator** | XSanity 0.96.0 (proprietary) | Xlibre (community StepMania fork, GPL) |
| **Audio** | ALSA | ALSA |
| **GPU: 8400GS** | nvidia-legacy-340xx-driver | Trix community patches + dkms (AUR-derived) |
| **GPU: 9300GS/GT** | nvidia-legacy-390xx-driver / 470 | Trix community + dkms |
| **PIUIO/LXIO Bridge** | djpohly/piuio kernel kmod (archived, breaks ≥5.7) | **PIUIO2Key-Linux** (userspace pyusb→uinput, Python, maintained) |
| **usbhid 1ms patch** | Kernel module rebuild (5.10-specific) | Trivially portable to 6.x; no structural hid-core.c changes |
| **Apt Repos** | Official bullseye | Trixie official + community repos (e.g., Netrunner 26 default) |
| **EOL** | 2026-08 | 2028-06 |

### PIUIO2Key-Linux Discovery

**GitHub**: `carlos-garcia/PIUIO2Key-Linux` (recent, active).

**Advantages over djpohly/piuio kmod**:
- **Userspace Python**: no kernel coupling, no module rebuild per kernel version.
- **Cross-device**: PIUIO (0547:1002), LXIO (0d2f:1020 / 0d2f:1040), plus extensible USB HID abstractions.
- **Polling**: 1000 Hz default, configurable.
- **UInput bridge**: exports panel inputs as standard Linux joystick events → XSanity + Xlibre both consume transparently.
- **Maintenance**: GPL-licensed, community-backed; no vendor lock-in on kernel module.

**Integration**: systemd user service (or session helper) on boot; auto-restarts if processes die.

### GPU Auto-Pick Strategy (Option B)

**Goal**: no manual GPU selection needed; user boots, first-run detects PCI ID → loads correct driver.

**Mechanism**:
1. **Build time**: compile nvidia-legacy-340/390/470 LKMs + libs as pre-built module bundles.
   - Store at `lib/gpu-drivers/340/uname-r/`, etc. (keyed by kernel version).
   - Include `.ko` files + any version-specific compatibility shims.

2. **First boot**: `firstboot.sh` runs before XSanity launch.
   - Query `lspci | grep -i nvidia`: extract Device ID (e.g., `10de:0395` for 8400GS).
   - Lookup table: Device ID → driver choice (340 for 03-series, 390 for GF, 470 for GK+).
   - Copy correct `.ko` + libs into live system.
   - `depmod -a`, `update-initramfs`.
   - *Optional reboot* if modules not loadable in-place (conservative path).

3. **Cold start** (next boot after reboot): correct driver loads; set once per install.

**Fallback**: if no match or lspci fails, default to newest driver (470) with warning in log.

### MK Series Expansion

**Trixie + Xlibre + PIUIO2Key** unlocks:

| Model | CPU | RAM | GPU | Display | IO | Status |
|---|---|---|---|---|---|---|
| **MK9v1** | Celeron E3400–Core 2 Quad | 4 GB DDR2 | 8400GS | HDMI/DVI/VGA 720p | PIUIO | ✅ MVP |
| **MK9v2** | Core 2 | 8 GB DDR3 | 9300GS / GT210 / GT610 / GT710 | same | PIUIO / LXIO | ✅ MVP |
| **MK6v2** | Core 2 Duo | 4 GB | 9400 GT / GT220 | same | PIUIO | 🎯 Post-MVP (trixie) |
| **MK10** | Ryzen 3 / 5 | 16 GB DDR4 | GTX 1050 / 1650 | 1080p + | LXIO v2 | 🎯 Post-MVP (trixie) |

**Xlibre** (community StepMania + Pump It Up stepfiles) also supports desktop play;
build can serve both cabinet + arcade-at-home market post-MVP.

### usbhid Patch on 6.x

kernel/usbhid-1ms.patch porting effort: **low**.
- ITG's patch targets 5.10.11; Debian 11 ships 5.10.0-39. Same major series, trivial application.
- Trixie ships 6.1+ or 6.x. hid-core.c structure unchanged fundamentally; offset adjustments only.
- Revalidate on first trixie test cabinet but no deep rework expected.

## Tested Combinations Matrix (to populate during Phase 1+)

| BootInSanity | Debian ISO | XSanity | MK9 | GPU | Status |
|---|---|---|---|---|---|
| v0.1 | debian-11.11.0-amd64-DVD-1.iso | 0.96.0 | v1 | 8400GS | TBD |
| v0.1 | debian-11.11.0-amd64-DVD-1.iso | 0.96.0 | v2 | GT710 | TBD |

## Out of Scope (MVP)

- Saninet (XSanity online — post-MVP).
- 15 kHz CRT support.
- SD/SD15 cabinet modes (HD only).
- Lighting board configuration UI (Win+C in ITG).
- **Cabinet lights** (panel halogens, marquee, neon, LIT buttons). XSanity
  0.96.0 has no native PIUIO lights driver — see "Cabinet Lights — Post-MVP"
  below.
- Auto-update over network.
- Memory card profiles.
- ARM / non-x86 hosts.
- macOS / Windows build hosts (Linux-only).

## Cabinet Lights — Post-MVP (deferred)

XSanity 0.96.0's only suitable LightsDriver is `Export`, which writes a
sextet-encoded bit stream to `Save/StepMania-Lights-SextetStream.out` (a
FIFO). No native `LightsDriver_PIUIO_Leds` (that exists only in ITGmania).

Path to working PIUIO cabinet lights:

1. Set `LightsDrivers=Export` in `/mnt/xsanity/Save/Preferences.ini`.
2. Ship a small userspace bridge daemon that:
   - Opens the SextetStream FIFO read-only.
   - Decodes each sextet char (printable 0x30–0x6F, 6 bits per char).
   - Maps StepMania's light-index ordering (defined in
     `LightsManager.h` upstream) to PIUIO output indices: panel up/down/
     left/right per player, cabinet bass-light L/R, marquee bulbs, etc.
   - Writes 0/1 to `/sys/class/leds/piuio::outputN/brightness` (exposed
     by djpohly/piuio kmod).
3. systemd unit on the installed system: `bootinsanity-lights.service`,
   waits for FIFO existence, restarts if XSanity restarts.
4. Optionally: per-cabinet light-map config file in `/mnt/xsanity/` so
   different cabinet wirings can be tweaked without rebuilding the image.

Estimate: ~150 LOC C or Python. One real MK9 lighting harness needed for
mapping verification.
