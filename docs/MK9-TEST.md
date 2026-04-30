# MK9 Hardware Test

Specifics for testing BootInSanity on a real MK9 cabinet. Build instructions
in [README](../README.md).

## Build flag per cabinet GPU

| Cabinet GPU | `GPU=` |
|---|---|
| 8300GS / 8400GS / 9300GS / GT210 / GT220 | `340` |
| GT4xx / GT5xx / GT610 (Fermi) | `390` |
| GT630 (Kepler) / GT710+ | `470` |

Boot menu defaults to **Clean Install** (10 s timeout). Wipes target disk,
partitions 3-way, GRUB hybrid BIOS+EFI.

Default credentials: `pump` / `pump`. SSH on port 22.

## Validation (SSH from LAN)

```bash
uname -r                                                  # 5.10.0-39-amd64
lsmod | grep -E 'usbhid|piuio|nvidia'
cat /sys/module/usbhid/parameters/{kb,js,else,mouse}poll  # all 1
lspci -k | grep -A2 -i nvidia                             # driver: nvidia
glxinfo | grep -i 'opengl renderer'                       # not llvmpipe / nouveau
```

In-game: F3 to toggle stats, confirm 60 fps on song select + gameplay.

## Bug reports — collect

- `uname -r`, `lsmod`, `/sys/module/usbhid/parameters/elsepoll`
- `dmesg | grep -iE 'nvidia|piuio|usbhid' | head -50`
- `grep -E '\(EE\)|\(WW\)' /var/log/Xorg.0.log | head -30`
- `tail -100 /tmp/bootinsanity-launch.log`
- FPS observed in-game
- PIUIO panel + test-menu response

## Failure modes

| Symptom | Likely cause |
|---|---|
| GRUB rescue prompt | install / grub | check `dmesg`, partition layout |
| Black screen after autologin | X or driver | `Xorg.0.log` |
| XSanity crash-loop | launcher | `bootinsanity-launch.log` |
| Inputs dead | PIUIO kmod / udev | `dmesg \| grep piuio`, `/etc/udev/rules.d/24-andamiro.rules` |

## Adding songs

```bash
scp -r Songs/ pump@<mk9-ip>:/mnt/xsanity/Songs/
ssh pump@<mk9-ip> sudo reboot
```

Cache regenerates on first launch after reboot.

## Updates

Boot install medium → pick **Update**. Re-flashes rootfs only; preserves
XSanity, Songs, Save, Cache on the data partition.
