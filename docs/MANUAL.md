# BootInSanity System Manual

## Introduction

BootInSanity is a dedicated Linux operating system that provides XSanity to Andamiro MK9 cabinet owners and arcade maintainers. It is designed to be a turnkey, embedded installation that boots directly into the game and can be powered off at any time.

The system is built on Debian 13 (trixie) with kernel 6.12 and targets 1280x720 at 60fps on original MK9 hardware.

## Goals

- Easy installation and maintenance with an updatable system image
- XSanity running at full speed on original Andamiro MK9 hardware
- PIUIO support out of the box — no configuration required
- System mode accessible via keyboard for operator maintenance
- Songs, save data, and settings preserved across system updates
- Safe to power off at any time

---

## Technical Information

### Supported Hardware

BootInSanity is designed and validated for the **Andamiro MK9** cabinet.

| Component | Spec |
|---|---|
| CPU | Intel Core 2 Quad (MK9 stock) |
| GPU | NVIDIA GeForce (nouveau driver) |
| RAM | 4 GB |
| Storage | 120 GB+ SATA SSD recommended |
| Display | 1280x720 HDMI/DVI |
| IO board | Andamiro PIUIO (USB 0547:1002) |
| Audio | Realtek ALC662 (onboard) |

### Disk Layout

| Partition | Size | Purpose |
|---|---|---|
| p1 | 256 MB | Boot (BIOS MBR + UEFI ESP) |
| p2 | 8 GB | System — re-flashed on update |
| p3 | Rest of disk | XSanity data: Songs, Save, Cache — **preserved on update** |

### Default Credentials

| | |
|---|---|
| Username | `pump` |
| Password | `pump` |
| Static IP (over ethernet) | 192.168.100.2 |
| SSH port | 22 |

---

## Installation Requirements

1. USB flash drive, 16 GB or larger
2. A second computer to write the USB (Linux or Windows)
3. USB keyboard for the cabinet during installation
4. The BootInSanity ISO image

> **WARNING: ALL DATA ON THE TARGET DRIVE WILL BE ERASED during a Clean Install.**

---

## Creating the Installation USB

### Linux

```bash
sudo dd if=bootinsanity-installer.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Replace `/dev/sdX` with your USB drive device (e.g. `/dev/sdb`). Double-check with `lsblk` before running — writing to the wrong device will destroy data.

### Windows

Use [Rufus](https://rufus.ie/) or [balenaEtcher](https://etcher.balena.io/):

1. Open Rufus or Etcher
2. Select the BootInSanity ISO
3. Select your USB drive
4. Click Start / Flash
5. Wait for completion, then safely eject the drive

---

## Installing on the Cabinet

1. Power off the cabinet
2. Plug the USB drive into a rear USB port on the motherboard
3. Plug in a USB keyboard
4. Power on the cabinet
5. Press the BIOS boot menu key repeatedly as soon as the screen lights up
   - On MK9 (Intel board): usually **F12**, **F2**, or **Del**
   - It is printed briefly on the screen during POST
6. Select the USB drive from the boot menu
7. Wait for the BootInSanity installer menu to appear:

```
  BootInSanity vX.X -- Installer
  ------------------------------
  Clean Install
  Update
```

8. Select **Clean Install** with the arrow keys and press Enter
   - Use **Update** if you already have BootInSanity installed and want to preserve your songs and save data
9. The installer shows a disclaimer and lists available disks. If only one disk is found it is selected automatically; otherwise type the number of the correct disk and press Enter
   - **If a disk is flagged as a possible PIU/game disk, read the warning carefully before proceeding**
10. When prompted, type `YES` (in capitals) and press Enter to confirm disk erasure
10. Wait for installation to complete — the cabinet will reboot automatically
11. Remove the USB drive after the reboot
12. The system will boot directly into XSanity

> **Note:** First boot after installation takes slightly longer — XSanity rebuilds its song cache. This is normal.

---

## Updating the System Image

The update flow re-flashes the system partition (p2) only. **Songs, save data, and XSanity settings on p3 are fully preserved.**

To update:

1. Write the new BootInSanity ISO to a USB drive (same process as above)
2. Boot from the USB drive
3. Select **Update** from the installer menu
4. Wait for completion — the cabinet reboots automatically

No song or settings reconfiguration is needed after an update.

---

## Operation

The system operates in two modes: **Game Mode** and **System Mode**.

### Game Mode

The cabinet boots directly into XSanity. The game runs in a crash-loop — if XSanity exits unexpectedly it restarts automatically.

The system can be powered off at any time using the cabinet power switch.

Things to note:
- A USB keyboard can be plugged in at any time for game navigation
- PIUIO is detected automatically — no configuration required
- Cabinet lights work out of the box

### System Mode

System mode allows the operator to perform maintenance tasks: adjusting volume, adding songs, resetting settings, rebooting, and more.

**To enter System Mode:**

1. Plug a USB keyboard into any USB port on the cabinet
2. Press **Win + F4**
3. A terminal window opens with the keybind menu
4. If the game window is still visible, press **Alt + F4** to dismiss it

**To return to the game from System Mode:**

Press **Win + G**, or reboot with **Win + B**.

### System Mode Keybinds

| Shortcut | Action |
|---|---|
| Win + F4 | Enter System Mode (kill game, open terminal) |
| Win + G | Return to game |
| Win + S | Add songs from USB stick |
| Win + V | Volume mixer (alsamixer) |
| Win + R | Reset XSanity settings |
| Win + E | Input device polling rate check |
| Win + X | Expand data partition to fill disk |
| Win + B | Reboot |
| Win + P | Power off |
| Win + Enter | Open new terminal |

> **Always use Win + P or Win + B to shut down.** Do not flip the power switch while in System Mode.

---

## Maintenance Tasks

### Adding Songs from USB

1. Copy your content onto a USB stick — any combination of:
   - `Songs/`, `SongMovies/`, `Avatars/`, `NoteSkins/` — always overwritten
   - `Save/` — only newer files are copied (profiles are never downgraded)
2. Plug the USB stick into the cabinet
3. Enter System Mode (Win + F4)
4. Press **Win + S**
5. A terminal opens, detects the USB stick, and shows what will be copied
6. Confirm with `Y`
7. Watch progress — all files are listed as they copy
8. When done, choose whether to reboot (required to rebuild the song cache)

Songs are copied to the data partition (p3) and are preserved across system updates.

### Adding Songs over the Network

Requires an ethernet cable between your laptop and the cabinet.

The cabinet has a static IP: **192.168.100.2**. Configure your laptop with a static IP on the same subnet (e.g. 192.168.100.1/24).

Use the included `push-songs.sh` script from your laptop. Pass the folder that **contains** your content directories:

```
XSanity/
  Songs/
  SongMovies/
  Avatars/
  NoteSkins/
  Save/
```

```bash
# From the BootInSanity repo directory:
./scripts/push-songs.sh /path/to/XSanity/

# Custom arcade IP:
./scripts/push-songs.sh /path/to/XSanity/ 192.168.1.50
```

The script copies whichever directories exist inside that folder. `Songs/`, `SongMovies/`, `Avatars/`, `NoteSkins/` are always overwritten. `Save/` uses keep-most-recent — profiles on the cabinet are never downgraded.

#### SSH Access (advanced)

```bash
ssh pump@192.168.100.2
# Password: pump
```

Songs live at `/mnt/xsanity/Songs/` on the cabinet.

### Adjusting Volume

1. Enter System Mode (Win + F4)
2. Press **Win + V**
3. Adjust levels in alsamixer using arrow keys
4. Press Escape when done

### Resetting XSanity Settings

Deletes the XSanity `Save/` directory, which contains settings and scores. XSanity will regenerate defaults on next launch.

1. Enter System Mode (Win + F4)
2. Press **Win + R**
3. Confirm when prompted
4. Return to game with **Win + G** or reboot with **Win + B**

### Expanding the Data Partition

If you replaced the drive with a larger one, p3 may not use the full available space. To expand it:

1. Enter System Mode (Win + F4)
2. Press **Win + X**
3. The partition is expanded automatically
4. Reboot with **Win + B**

---

## Troubleshooting

| Symptom | First check |
|---|---|
| Black screen after boot | SSH in, check `/tmp/bootinsanity-launch.log` |
| XSanity crash loop (restarts every few seconds) | Same log; check last error. Win+F4 to enter system mode |
| No sound | Win+V → check Master and PCM are unmuted and at 100% |
| PIUIO not responding | Check USB cable. Run `ls /sys/bus/usb/devices/*/idProduct` via SSH — should see `1002` |
| No keyboard input in game | Ensure hotkey watcher is running: `systemctl status bootinsanity-hotkeys` |
| p3 full, no space for songs | Win+X to expand, or SSH and check `df -h /mnt/xsanity` |
| Forgot to remove USB after install | Remove USB, reboot — system boots from internal drive |

---

## Changelog

### v0.1-rc6
- Add songs via USB (Win+S) now copies Songs, SongMovies, Avatars, NoteSkins
- `push-songs.sh`: laptop-side script for network song transfer

### v0.1-rc5
- Win+G: return to game from system mode
- Win+S: add songs from USB stick
- Static arcade IP (192.168.100.2) — no manual setup needed after reboot
- Drop unnecessary sleep in system mode exit

### v0.1-rc4
- Audio capture ADC switch now properly disabled at boot (hum fix)
- ISO size reduced: Cache excluded from image, old kernels purged at build time
- `usbutils` (lsusb) included for diagnostics

### v0.1-rc3
- Keyboard input restored in game and installer (evdev grab removed from hotkey watcher)
- Hotkey watcher now only watches real keyboards (excludes PIUIO and mice)

### v0.1-rc2
- evdev-level hotkey watcher (Win+key shortcuts work even while XSanity grabs keyboard)
- piuio2key removed — XSanity reads PIUIO natively, no bridge needed
- ALSA capture paths muted at boot to prevent loopback hum
- pumptools removed (multi-boot out of scope)
- Kernel module build removed (PIUIO is not a HID device)

### v0.1-rc1
- Initial hardware test on MK9
- XSanity running: video, PIUIO, cabinet lights all working
- Audio functional (hum present, fixed in rc2)
