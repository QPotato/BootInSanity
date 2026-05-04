# MK9 Hardware Test

Checklist for testing BootInSanity on a real MK9 cabinet.

## Build the ISO

```bash
make iso \
  DEBIAN_ISO=debian-13.x-amd64-DVD-1.iso \
  "XSANITY_DIR=XSanity 0.96.0/XSanity" \
  VERSION=v0.1-rc2 \
  GPU=nouveau
```

Write to USB: `sudo dd if=build/bootinsanity-installer.iso of=/dev/sdX bs=4M status=progress oflag=sync`

Default credentials: `pump` / `pump`. SSH port 22.

## SSH via direct ethernet

On laptop: `nmcli con add type ethernet ifname <iface> con-name arcade ip4 192.168.100.1/24 ipv4.method manual && nmcli con up arcade`

On arcade (via Win+F4 → terminal): `sudo ip addr add 192.168.100.2/24 dev <iface>`

Then: `ssh -o PubkeyAuthentication=no pump@192.168.100.2`

## Live boot validation

| Check | Command | Expected |
|---|---|---|
| Kernel version | `uname -r` | `6.12.x+deb13-amd64` |
| XSanity running | `pgrep -a XSanity` | process listed |
| PIUIO visible | `lsusb \| grep 0547` | `0547:1002` present |
| ALSA device | `aplay -l` | ALC662 or HDA Intel listed |
| Sound test | `aplay /usr/share/sounds/freedesktop/stereo/bell.oga` | audible, no hum |
| Hotkey watcher | `systemctl status bootinsanity-hotkeys` | active (running) |
| Logs | `tail -50 /tmp/bootinsanity-launch.log` | XSanity started, no crash loop |

## System mode keybinds (Win = Super key)

| Key | Expected |
|---|---|
| Win+F4 | Kills XSanity, drops to lxterminal with keybind menu |
| Win+Enter | Opens new lxterminal |
| Win+V | Launches alsamixer |
| Win+B | Reboots |
| Win+P | Powers off |
| Win+R | Resets XSanity settings (deletes Save/) |
| Win+M | Opens file manager at /media/pump |
| Win+X | Expands p3 to fill disk |

## Adding songs

```bash
scp -r Songs/ pump@192.168.100.2:/mnt/xsanity/Songs/
ssh pump@192.168.100.2 sudo reboot
```

Cache regenerates on first launch after reboot.

## Update (re-flash p2, preserve p3)

Boot install medium → **Update** from GRUB menu. Or test with:
```bash
make qemu-update
```

## Failure modes

| Symptom | First check |
|---|---|
| GRUB rescue prompt | `lsblk` on cabinet, check 3 partitions present |
| Black screen after boot | `cat /tmp/bootinsanity-launch.log` via SSH |
| XSanity crash loop | Same log; check 3-crash system mode fallback |
| No sound | `amixer` — confirm Master/PCM unmuted; `aplay -l` for device |
| Win+F4 no response | `systemctl status bootinsanity-hotkeys` — should be active |
