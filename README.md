# BootInSanity

Linux live-installer image for running the XSanity Pump It Up simulator on
Andamiro MK9 arcade hardware. Modeled after the ITG (In The Groove) system
image, built on Debian 11 LTS.

## Status

Active development. Phases 0–2 working in QEMU; Phase 3 (kernel modules,
NVIDIA drivers) in progress, pending real-MK9 validation.

## Requirements (build host)

- Linux x86_64
- Docker (with `--privileged` support)
- QEMU/KVM for testing (`qemu-system-x86_64`)
- A Debian 11 DVD-1 ISO (`debian-11.x.0-amd64-DVD-1.iso`,
  https://cdimage.debian.org/cdimage/archive/11.11.0/amd64/iso-dvd/)
- A copy of XSanity 0.96.0 (https://download.xsanity.net/XSanity%200.96.0.tar.xz)

The user supplies the Debian ISO and the XSanity folder. Neither is
redistributed by this project.

## Quick start

```bash
make builder

make iso \
  DEBIAN_ISO=~/Downloads/debian-11.11.0-amd64-DVD-1.iso \
  XSANITY_DIR=~/Downloads/XSanity \
  GPU=nouveau            # or 340 / 390 / 470 per cabinet GPU
  OUTPUT=build/bootinsanity-installer.iso

# Live boot (no install)
make qemu

# Install onto a 16 GB virtio target disk, then boot it
make qemu-install
make qemu-installed
```

Boot menu on the resulting ISO:

- **Clean Install** — wipes target disk, partitions 3-way (256 MB boot +
  8 GB rootfs + rest data), unsquashfs, GRUB hybrid BIOS+EFI install.
- **Update** — re-flashes the rootfs partition only; preserves XSanity,
  Songs, Save, and Cache on the data partition.
- **Live Boot** — runs entirely from USB, no installation.

## GPU driver picking

| `GPU=` | Driver bundled | Covers |
|---|---|---|
| `nouveau` (default) | xserver-xorg-video-modesetting | every GPU (open-source fallback) |
| `340` | nvidia-legacy-340xx-driver | GeForce 8400GS / 9300GS / GT210 / GT220 |
| `390` | nvidia-legacy-390xx-driver | GeForce GT4xx / GT5xx / GT610 (Fermi) |
| `470` | nvidia-driver | GeForce GT630 (Kepler) / GT710+ |

One ISO per cabinet GPU family. Rebuild as needed.

## Other targets

```bash
make help        # list all targets
make shell       # drop into the builder container
make clean       # remove work/ and build/
make distclean   # also remove the builder Docker image
```

## Repository layout

```
.
├── Dockerfile                 # builder image (debian:bullseye-slim + tooling)
├── Makefile                   # make iso / qemu / qemu-install / shell / clean
├── build.sh                   # main build script
├── overlay/                   # files copied into the chroot rootfs
│   ├── etc/                   # X11, udev, systemd, modprobe, modules-load
│   ├── home/pump/             # i3, .xinitrc, .bash_profile (autologin → X)
│   ├── opt/bootinsanity/      # XSanity launcher, missing-XSanity screen
│   └── opt/bootinsanity-installer/  # disk-install script
├── kernel/                    # out-of-tree kernel modules
│   ├── usbhid-1ms.patch       # forces 1ms polling on all USB HID devices
│   └── build-kmods.sh         # builds patched usbhid + djpohly/piuio
└── README.md
```

## Credits

- ITG image (Mike Solomon, dinsfire64) — udev rules, usbhid 1ms patch, and
  the overall arcade-image design
  (https://github.com/dinsfire64/itgmania-system)
- djpohly/piuio — Andamiro PIUIO board → Linux input driver
  (https://github.com/djpohly/piuio)
- XSanity team — the simulator (https://xsanity.net/)

## License

Build scripts: MIT (see `LICENSE`).

The Debian base system, XSanity simulator, and NVIDIA legacy drivers are
governed by their own licenses and are obtained at build time on the user's
machine. They are not redistributed by this project.
