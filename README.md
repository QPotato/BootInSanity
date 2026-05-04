# BootInSanity

Linux live-installer image for running the XSanity Pump It Up simulator on
Andamiro MK9 arcade hardware. Built on Debian 13 (trixie), kernel 6.x.

## Status

**Branch: trixie-xlibre** — active development.

| Phase | Status |
|---|---|
| 0+1 Debian 13 live + XSanity | ✅ Hardware validated |
| 2 Installer (clean + update) | ✅ QEMU validated |
| 3 PIUIO/LXIO udev + pumptools | ✅ Hardware validated |
| 3c NVIDIA legacy drivers | 🔴 GPU=nouveau only |
| 4 System mode (Win+key) | 🟡 evdev watcher implemented, pending hardware retest |
| 5 Branding + user manual | 🔴 not started |

Hardware test (v0.1-rc1, live mode): sound ✅ video ✅ PIUIO input ✅ cabinet lights ✅

## Requirements (build host)

- Linux x86_64
- Docker (with `--privileged` support)
- QEMU/KVM for testing (`qemu-system-x86_64`)
- Debian 13 DVD-1 ISO (`debian-13.x-amd64-DVD-1.iso`)
- XSanity 0.96.0 folder

The user supplies the Debian ISO and the XSanity folder. Neither is
redistributed by this project.

## Quick start

```bash
make builder

make iso \
  DEBIAN_ISO=~/Downloads/debian-13.x-amd64-DVD-1.iso \
  XSANITY_DIR="~/Downloads/XSanity 0.96.0/XSanity" \
  VERSION=dev

# Live boot test (no install)
make qemu

# Install + boot cycle
make qemu-install   # boot ISO with a virtio target disk attached
make qemu-installed # boot from installed disk (no ISO)

# Test update flow (preserves p3)
make qemu-update
```

Boot menu on the resulting ISO:

- **Clean Install** — wipes target disk, partitions 3-way (256 MB boot +
  8 GB rootfs + rest data), unsquashfs, GRUB hybrid BIOS+EFI.
- **Update** — re-flashes rootfs only; preserves XSanity, Songs, Save on data partition.
- **Live Boot** — runs entirely from USB, no installation.

## Writing to USB (hardware install)

```bash
lsblk  # identify your USB device, e.g. /dev/sdb
sudo dd if=build/bootinsanity-installer.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Boot the MK9 cabinet from USB. Select **Clean Install** (or **Live Boot** to
test without writing to disk). Default credentials: `pump` / `pump`.

## Disk layout

| Partition | Size | Mount | Purpose |
|---|---|---|---|
| p1 | 256 MB | `/boot/efi` | ESP + BIOS boot |
| p2 | 8 GB | `/` | System rootfs |
| p3 | rest of disk | `/mnt/xsanity` | XSanity + Songs + Save + Cache |

Update re-flashes p2 only; p3 survives across updates.

## System mode keybinds

Implemented via evdev watcher (`bootinsanity-hotkeys.service`) — works even
when XSanity has grabbed the keyboard.

| Key | Action |
|---|---|
| **Win+F4** | Kill XSanity, drop to desktop |
| Win+Enter | New terminal |
| Win+M | Memory cards (file manager at /media/pump) |
| Win+R | Reset XSanity settings (deletes Save/) |
| Win+V | Volume mixer (alsamixer) |
| Win+E | Input polling rate check (evtest) |
| Win+X | Expand data partition to fill disk |
| Win+B | Reboot |
| Win+P | Power off |

## GPU

`GPU=nouveau` is the only supported option on this branch. Legacy NVIDIA
packages (340/390/470) for Debian 13 are not yet implemented.

## Repository layout

```
.
├── Dockerfile                  # builder image (debian:trixie-slim + tooling)
├── Makefile                    # make iso / qemu / qemu-install / qemu-installed / qemu-update / shell / clean
├── build.sh                    # main build script
├── overlay/                    # files copied into the chroot rootfs
│   ├── etc/                    # X11, udev, systemd, modprobe, sudoers
│   ├── home/pump/              # i3 config, .xinitrc, .bash_profile
│   ├── opt/bootinsanity/       # launcher, hotkey watcher, system-mode scripts
│   └── opt/bootinsanity-installer/  # disk installer script
└── docs/
    └── MK9-TEST.md             # hardware test checklist
```

## Credits

- ITG image (Mike Solomon, dinsfire64) — udev rules, overall arcade-image
  design (https://github.com/dinsfire64/itgmania-system)
- pumpitupdev/pumptools — PIU legacy game compatibility layer
- XSanity team — the simulator (https://xsanity.net/)

## License

Build scripts: PolyForm Noncommercial 1.0.0 (see `LICENSE`).

The Debian base system and XSanity simulator are obtained at build time on
the user's machine under their respective licenses and are not redistributed.
