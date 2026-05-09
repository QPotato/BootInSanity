# BootInSanity

Linux live-installer image for running the XSanity Pump It Up simulator on arcade cabinets. Built on Debian 13 (trixie).

Project is heavily vibe-coded and you run it **at your own risk**.

## Status

Tested on my MK9, works with some frame drops on song selection but gameplay is then fine.

Couldn't get propietary drivers to work yet, so we are running on [nouveau](https://nouveau.freedesktop.org/).

See [PROGRESS.md](PROGRESS.md) for the full slop version progress tracking by Caude.

# Downloads

You can download the prebuilt image with stock XSanity 0.96 (no songs or other content) from here:


You will need to transfer the content via rsync or USB later. Come to think about it, I didn't test the USB yet lmao.

## Building

Alternatively, you can build your disk image with your XSanity folder ready to play.

- Linux x86_64
- Docker (with `--privileged` support)
- QEMU/KVM for testing (`qemu-system-x86_64`)
- Debian 13 DVD-1 ISO (`debian-13.x-amd64-DVD-1.iso`)
- XSanity folder with all your content already installed

```bash
make builder

make iso \ 
  DEBIAN_ISO=/path/to/debian-13.x-amd64-DVD-1.iso \ 
  XSANITY_DIR=/path/to/XSanity \ 
```

Boot menu on the resulting ISO:

- **Clean Install** — wipes target disk, partitions 3-way (256 MB boot +
  8 GB rootfs + rest data), unsquashfs, GRUB hybrid BIOS+EFI.
- **Update** — re-flashes rootfs only; preserves XSanity, Songs, Save on data partition.
- **Live Boot** — runs entirely from USB, no installation. No idea if it saves progress, someone should test.

## Writing to USB drive.

```bash
lsblk  # identify your USB device, e.g. /dev/sdb
sudo dd if=build/bootinsanity-installer.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Or use some GUI tool. Be careful with the drive you select, obviously. You will wipe your drive.

## Testing in QEMU (for development)

```bash
# Live boot test (no install)
make qemu

# Install + boot cycle
make qemu-install   # boot ISO with a virtio target disk attached
make qemu-installed # boot from installed disk (no ISO)

# Test update flow (preserves p3)
make qemu-update
```


## Disk layout

| Partition | Size | Mount | Purpose |
|---|---|---|---|
| p1 | 256 MB | `/boot/efi` | ESP + BIOS boot |
| p2 | 8 GB | `/` | System rootfs |
| p3 | rest of disk | `/mnt/xsanity` | XSanity + Songs + other content + Save + Cache |

Update re-flashes p2 only; p3 survives across updates.

## System mode keybinds

Implemented via evdev watcher (`bootinsanity-hotkeys.service`) — works even
when XSanity has grabbed the keyboard.

| Key | Action |
|---|---|
| **Win+F4, Alt+F4** | Kill XSanity, drop to console |
| Win+Enter | New terminal |
| Win+R | Reset XSanity settings (deletes Save/) |
| Win+V | Volume mixer (alsamixer) |
| Win+E | Input polling rate check (evtest) |
| Win+X | Expand data partition to fill disk |
| Win+B | Reboot |
| Win+P | Power off |

Not sure if all of this is implemented actually.

## Credits

- ITG image (Mike Solomon, dinsfire64) — udev rules, overall arcade-image
  design (https://github.com/dinsfire64/itgmania-system)
- pumpitupdev/pumptools — PIU legacy game compatibility layer
- XSanity team — the simulator (https://xsanity.net/)

## License

Build scripts: PolyForm Noncommercial 1.0.0 (see `LICENSE`).

The Debian base system and XSanity simulator are obtained at build time on
the user's machine under their respective licenses and are not redistributed.
