# BootInSanity

Linux live-installer image for running the XSanity Pump It Up simulator on
Andamiro MK arcade hardware. Built on Debian 13 (trixie), kernel 6.x.

## Status

**Branch: trixie-xlibre** — active development target.

| Phase | Status |
|---|---|
| 0+1 Debian 13 live + XSanity | ✅ QEMU validated |
| 2 Installer (clean + update) | ✅ QEMU validated |
| 3a PIUIO2Key-Linux service | ✅ QEMU validated |
| 3b usbhid 1ms patch (6.x) | ✅ QEMU validated |
| 3c NVIDIA legacy drivers | 🔴 not yet (GPU=nouveau only) |
| 4 System mode (Win+key) | 🟡 committed, pending hardware |

## Requirements (build host)

- Linux x86_64
- Docker (with `--privileged` support)
- QEMU/KVM for testing (`qemu-system-x86_64`, `sshpass`)
- Debian 13 DVD-1 ISO (`debian-13.x-amd64-DVD-1.iso`)
- A copy of XSanity 0.96.0

The user supplies the Debian ISO and the XSanity folder. Neither is
redistributed by this project.

## Quick start

```bash
make builder

make iso \
  DEBIAN_ISO=~/Downloads/debian-13.0-amd64-DVD-1.iso \
  XSANITY_DIR="~/Downloads/XSanity 0.96.0" \
  VERSION=dev

# Live boot test (no install)
make qemu

# Install + boot cycle
make qemu-install   # boot ISO with a virtio target disk attached
make qemu-installed # boot from installed disk (no ISO)
```

Boot menu on the resulting ISO:

- **Clean Install** — wipes target disk, partitions 3-way (256 MB boot +
  8 GB rootfs + rest data), unsquashfs, GRUB hybrid BIOS+EFI install.
- **Update** — re-flashes rootfs only; preserves XSanity, Songs, Save on data partition.
- **Live Boot** — runs entirely from USB, no installation.

## GPU driver

`GPU=nouveau` (default, open-source modesetting) is the only supported option
on this branch. Legacy NVIDIA packages (340/390/470) for Debian 13 are pending.

## System mode keybinds (Phase 4)

| Key | Action |
|---|---|
| **Win+F4** | Kill XSanity, drop to desktop (crash-loop escape) |
| Win+Enter | New terminal |
| Win+M | Memory cards (file manager at /media/pump) |
| Win+R | Reset XSanity settings (deletes Save/) |
| Win+V | Volume mixer (alsamixer) |
| Win+E | Input polling rate check (evtest) |
| Win+X | Expand data partition to fill disk |
| Win+B | Reboot |
| Win+P | Power off |

> **QEMU note**: Super/Win key is intercepted by the host WM in QEMU GTK mode.
> Test these bindings on real hardware.

## Writing to USB (hardware test)

```bash
# Find your USB device (e.g. /dev/sdb)
lsblk

sudo dd if=build/bootinsanity-installer.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Boot the MK9 cabinet from USB. Select **Clean Install** (or **Live Boot** to
test without writing to disk).

## Repository layout

```
.
├── Dockerfile                 # builder image (debian:trixie-slim + tooling)
├── Makefile                   # make iso / qemu / qemu-install / qemu-installed / shell / clean
├── build.sh                   # main build script
├── overlay/                   # files copied into the chroot rootfs
│   ├── etc/                   # X11, udev, systemd, modprobe, sudoers
│   ├── home/pump/             # i3 config, .xinitrc, .bash_profile
│   ├── opt/bootinsanity/      # launcher, missing-XSanity screen, piu-launch
│   │   └── system-mode/       # Win+key utility scripts
│   └── opt/bootinsanity-installer/  # disk-install script
└── kernel/
    ├── usbhid-1ms.patch       # 5.x patch (reference)
    ├── patch-usbhid.py        # Python transform — applies to 5.x and 6.x
    ├── build-kmods.sh         # 5.x kmod builder (bullseye)
    └── build-kmods-6x.sh      # 6.x kmod builder (trixie)
```

## Credits

- ITG image (Mike Solomon, dinsfire64) — udev rules, usbhid 1ms patch, overall
  arcade-image design (https://github.com/dinsfire64/itgmania-system)
- djpohly/piuio — Andamiro PIUIO board kernel module (reference; replaced on
  6.x by PIUIO2Key-Linux)
- carlos-garcia/PIUIO2Key-Linux — userspace PIUIO/LXIO → uinput bridge
- pumpitupdev/pumptools — PIU legacy game compatibility layer
- XSanity team — the simulator (https://xsanity.net/)

## License

Build scripts: PolyForm Noncommercial 1.0.0 (see `LICENSE`).

Files under `kernel/` derive from the Linux kernel and are licensed GPLv2.

The Debian base system, XSanity simulator, pumptools, and PIUIO2Key-Linux are
obtained at build time on the user's machine under their respective licenses.
They are not redistributed by this project.
