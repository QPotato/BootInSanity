# BootInSanity — Progress Report

Status snapshot of the BootInSanity project (was: saniboot). Companion to
[PLAN.md](PLAN.md).

Last updated: 2026-05-03

## TL;DR

### main branch (bullseye, MK9 target)
- Phase 0 ✅ — bare Debian 11 live ISO boots in QEMU.
- Phase 1 ✅ — XSanity launches at 1280x720, keyboard input + audio + SSH working in QEMU.
- Phase 2 ✅ — Installer wraps live ISO. Clean Install partitions target disk (256M boot + 8G rootfs + rest data), unsquashfs, GRUB hybrid BIOS+EFI install. Installed system boots from disk → autologin → X → XSanity.
- Phase 3a ✅ — Kernel modules: patched usbhid (1 ms polling) + djpohly/piuio. ITG udev rules. Validated in QEMU.
- Phase 3b 🟡 — NVIDIA legacy drivers wired, pending real MK9 hardware test.

### trixie-xlibre branch (Debian 13, next-gen)
- Phase 0+1 ✅ — XSanity boots on Debian 13 trixie (kernel 6.12.73), 1280x720, audio + input working. Validated in QEMU 2026-05-03.
- Phase 2 ✅ — Installer validated (user-run). Installed system boots to XSanity. 2026-05-03.
- Phase 3a ✅ — PIUIO2Key-Linux service installed + enabled; pumptools hooks present; python3-usb OK. Validated in QEMU 2026-05-03.
- Phase 3b ✅ — usbhid.ko built with elsepoll param, vermagic matches 6.12.85. Validated in QEMU 2026-05-03.
- Phase 3c 🔴 — NVIDIA community packages not yet implemented (GPU=nouveau only on trixie).
- Phase 4 🟡 — System mode keybinds committed; Win+F4 untestable in QEMU (host WM intercepts Super key). Pending hardware validation.

Build pipeline working end-to-end on both branches. Dockerized, reproducible.

## Repository Layout (current)

```
saniboot/
├── README.md                   # quickstart, tested combos
├── PLAN.md                     # full design + phase plan
├── PROGRESS.md                 # this file
├── project.md                  # original brief from user
├── Dockerfile                  # builder: debian:bullseye-slim + tooling
├── Makefile                    # make builder / iso / qemu / shell / clean
├── build.sh                    # entrypoint script (root, runs in builder container)
├── .gitignore
├── overlay/                    # files copied into the chroot rootfs
│   ├── etc/
│   │   ├── X11/xorg.conf.d/10-screen.conf      # forces 1280x720
│   │   ├── modprobe.d/blacklist-pcspkr.conf
│   │   ├── sudoers.d/pump
│   │   └── systemd/system/getty@tty1.service.d/autologin.conf
│   ├── home/pump/
│   │   ├── .bash_profile       # auto-startx on tty1
│   │   ├── .xinitrc            # exec i3
│   │   └── .config/i3/config   # kiosk-mode i3 config
│   └── opt/bootinsanity/
│       ├── launch.sh           # XSanity crash-loop with debug aid
│       └── missing-xsanity.sh  # fullscreen "install XSanity" notice
├── ITG System Image Manual.pdf # reference doc
├── itg-v0-24/                  # reference ITG image (Clonezilla parts)
└── XSanity 0.96.0/             # user-supplied XSanity reference
```

## Build Pipeline (Phase 1 state)

### Inputs (user-supplied)

- Debian 11 DVD-1 ISO (`debian-11.11.0-amd64-DVD-1.iso`, ~3.7 GB).
  Downloaded from `https://cdimage.debian.org/cdimage/archive/11.11.0/`.
- XSanity 0.96.0 folder (`XSanity 0.96.0/XSanity/`) — already present in repo.

### Outputs

- `build/bootinsanity-installer.iso` (~849 MB, hybrid BIOS + UEFI live ISO).

### Invocation

```bash
make builder
make iso \
  DEBIAN_ISO=/home/fede/Downloads/debian-11.11.0-amd64-DVD-1.iso \
  XSANITY_DIR="/home/fede/code/saniboot/XSanity 0.96.0/XSanity" \
  VERSION=0.1-phase1
make qemu
```

### Build Steps (build.sh, 9 phases)

1. Mount Debian ISO loop.
2. `mmdebstrap bullseye → /work/work/chroot` from ISO + deb.debian.org fallback
   (DVD-1 doesn't include `live-boot`; deb.debian.org supplies it).
3. Apply `overlay/` rootfs.
4. Configure inside chroot: create `pump:pump` user, lock root, enable
   `ssh / NetworkManager / chrony / getty@tty1`, mask pulseaudio/pipewire, generate locale.
5. Inject XSanity: rsync `XSANITY_DIR/` → `/mnt/xsanity/`, create stub symlinks
   for `libpthread.so.0`, `libdl.so.2`, `librt.so.1`, `libresolv.so.2`,
   `libutil.so.1` → `libc.so.6` (XSanity bundles glibc 2.42 which merged these
   libs; without stubs the system 2.31 versions get loaded and break with
   GLIBC_PRIVATE symbol mismatch).
6. mksquashfs the chroot (xz, ~795 MB compressed).
7. Copy kernel + initrd from chroot.
8. Write isolinux (BIOS boot) + grub-efi (UEFI boot).
9. xorriso assembles hybrid ISO.

### Build environment

- Container: `debian:bullseye-slim` + `mmdebstrap dpkg-dev xorriso isolinux
  syslinux-common grub-pc-bin grub-efi-amd64-bin grub-common mtools
  dosfstools squashfs-tools parted zstd xz-utils ca-certificates file kmod
  rsync sudo procps`.
- Run with `docker --privileged` (needs loop-mount + chroot).

## Phase 0 — bare live ISO  ✅ DONE

- Debian 11.11 + linux-image-amd64 (5.10.0-32) + live-boot.
- No customization beyond hostname + issue.
- Boots in QEMU to `bootinsanity login:` prompt.
- Validated with `make qemu`. User confirmed login prompt visible.

## Phase 1 — X11 + i3 + ALSA + autologin + XSanity injection  ✅ DONE

### What works

- Auto-login as `pump:pump` on tty1 via systemd getty drop-in.
- `~/.bash_profile` auto-execs `startx` on tty1.
- `~/.xinitrc` execs `i3`.
- i3 loads our minimal kiosk config (after `# i3 config file (v4)` magic
  comment was added — without it, i3 auto-migrated as v3 and fell back to
  default `/etc/i3/config` which has a status bar).
- i3 autostart calls `/opt/bootinsanity/launch.sh`.
- Launch script crash-loops XSanity, logs to `/tmp/bootinsanity-launch.log`,
  drops to `lxterminal` after 3 consecutive crashes for debug.
- XSanity binary launches and renders correctly (title screen seen, menu
  navigable with arrow keys + Enter).
- `Win+Enter` in i3 opens `lxterminal` (debug escape hatch).
- `Win+B` reboots, `Win+P` powers off.
- sshd on port 22 (forwarded to host port 2222 in `make qemu`).
- pulseaudio/pipewire/wireplumber masked. ALSA only.

### All Phase 1 issues resolved

| Issue | Resolution |
|---|---|
| Visual cropping (XSanity in top-left of bigger X screen) | `overlay/etc/X11/xorg.conf.d/10-screen.conf` locks Xorg to 1280x720 via Modeline |
| No audio | XSanity Preferences key is `SoundDrivers` (plural) and accepts `ALSA-sw` (lowercase, hyphen). Found via `strings XSanity \| grep`: driver registry is `JACK,Pulse,ALSA-sw,OSS,Null`. launch.sh seeds `SoundDrivers=ALSA-sw` + `SoundDevice=default` |
| SSH "Too many authentication failures" | Cosmetic, host-side. Workaround: `ssh -o IdentitiesOnly=yes -o PreferredAuthentications=password,keyboard-interactive pump@localhost -p 2222`. Not a BootInSanity bug. |

### Significant fixes during Phase 1

| Symptom | Root cause | Fix |
|---|---|---|
| `make iso` failed: "nothing got downloaded -- use copy:// instead of file://" | mmdebstrap rejects file:// transport on local mount | Switched to `copy://` URI |
| `Can't locate Dpkg/Vendor/Debian.pm` | Builder Dockerfile missed `dpkg-dev` package | Added `dpkg-dev` to Dockerfile |
| `E: Unable to locate package live-boot` | live-boot not on Debian DVD-1 (it's on DVD-2/3) | Added deb.debian.org as fallback apt source in mmdebstrap |
| Cached chroot reused after failed build | Cache check was `[[ -d $CHROOT/usr ]]` (true even mid-fail) | Now checks for kernel: `compgen -G "$CHROOT/boot/vmlinuz-*"` |
| Make `$(abspath …)` mangled paths with spaces ("XSanity 0.96.0/") | Make treats space as path separator in `$(abspath)` | Stage XSanity into `work/inputs/xsanity/` (no spaces) before docker run |
| Permission denied creating `work/inputs` | Earlier docker runs created `work/` as root | One-shot `docker run … chown -R uid:gid /work/work` |
| i3bar "status command not found exit 127" black screen | Our i3 config lacked `# i3 config file (v4)` marker → i3 auto-migrated as v3 → fell back to `/etc/i3/config` (which has a bar with `status_command i3status`, and i3status wasn't installed in `--variant=minbase`) | Added v4 magic comment to user config |
| GLIBC_PRIVATE symbol mismatch (`__libc_pthread_init`) on XSanity launch | XSanity bundles glibc 2.42 (libc.so.6, libm.so.6, libmvec.so.1) but does NOT ship libpthread.so.0/libdl.so.2/librt.so.1 stubs. glibc 2.34+ merged those into libc itself. On Debian 11 host (glibc 2.31), system libpthread loaded → tries to bind to bundled libc 2.42 → mismatch. | build.sh creates symlinks: `libpthread.so.0 → libc.so.6` (and dl, rt, resolv, util) inside `/mnt/xsanity/lib/`. Bundled libc 2.42 satisfies all symbols. |
| Visual cropping (XSanity window in top-left of bigger X screen) | virtio-vga `xres=1280,yres=720` is initial size; modesetting may renegotiate | `xorg.conf.d/10-screen.conf` locks 1280x720 (in flight, not yet validated) |

## Phase 2 — Installer  ✅ DONE

Live ISO now also functions as an installer.

### Boot menu (isolinux + grub)

- **Clean Install** (default, 10s timeout): wipes target disk, partitions
  3-way (256M vfat boot + 8G ext4 rootfs + rest ext4 data), unsquashfs
  rootfs, moves XSanity to data partition, installs GRUB hybrid BIOS+EFI,
  reboots.
- **Update**: re-flashes p2 only. p1 + p3 (XSanity, Songs, Save) preserved.
- **Live Boot**: original Phase 1 behavior, no install.

### How it works

- `install=clean` or `install=update` kernel cmdline param triggers
  `bootinsanity-installer.service` (systemd `ConditionKernelCommandLine=install`).
- Service grabs tty1, runs `/opt/bootinsanity-installer/install.sh`.
- After completion, reboots into installed system.
- On normal boot (no install= param), service condition fails, getty@tty1
  runs as usual → autologin → XSanity.

### Bugs found + fixed during Phase 2

| Symptom | Root cause | Fix |
|---|---|---|
| GRUB rescue prompt after install | `mksquashfs -e boot` excluded `/boot` from squashfs → installed disk had no kernel/initrd/grub.cfg | Removed `-e boot` from mksquashfs |
| Floppy `fd0` listed as install target | lsblk reported it as TYPE=disk | install.sh skips `fd*`, `sr*`, `loop*`, `ram*`, `zram*` and disks <4 GB |
| Installed system boots to multi-user but tty1 dead, no XSanity | `Conflicts=getty@tty1.service` on installer.service blocked getty even when installer condition failed | Removed `Conflicts=`; added `Before=getty@tty1.service` instead |
| `sudo: /etc/sudoers.d is owned by uid 1000, should be 0` | `rsync -a overlay/` preserved host UIDs; /etc files ended up uid 1000 | After overlay rsync, `chown -R 0:0 chroot/etc chroot/opt` |

### QEMU validation

- `make qemu-install` boots ISO + virtio target disk (`build/qemu-target.qcow2`).
- `make qemu-installed` boots from the installed disk only.
- Full cycle verified: clean install → reboot → autologin → i3 → XSanity
  with audio + video.

## Phase 3 — NVIDIA legacy drivers + usbhid 1ms + PIUIO/LXIO

### 3a ✅ DONE (bullseye)

- **usbhid 1ms patch**: built from source kernel/usbhid-1ms.patch against bullseye 5.10.0-39, installed to `/lib/modules/{KVER}/updates/usbhid.ko`, initramfs rebuilt.
- **djpohly/piuio kmod**: cloned + built `mod/` against kernel headers, installed to `/lib/modules/{KVER}/extra/piuio.ko`.
- **ITG udev rules**: 8 rulefiles ported (20-minimaid, 21-pacdrive, 22-icedragon, 23-konami, 24-andamiro, hide-partitions, etc).
- **Kernel cmdline**: `kbpoll=1 jspoll=1 mousepoll=1 elsepoll=1` via overlay modprobe.d.
- **Validation**: QEMU boot shows both modules in-tree, depmod OK, initramfs includes patched usbhid.
- **Note**: djpohly/piuio archived 2019, breaks on kernel ≥5.7. Post-MVP (trixie branch) replaces with PIUIO2Key-Linux (userspace).

### 3b 🟡 PENDING

- **NVIDIA legacy driver**: GPU=340|390|470 build flag wired in build.sh but untested (no NVIDIA hw in QEMU).
- **Hardware test**: awaiting real MK9 (user has access, tester standby).
- **Next**: after RC1 validation, branch trixie-xlibre for next-gen work.

## PIU Legacy Multiboot via pumptools (main branch, bullseye)

### What was done

- `overlay/opt/bootinsanity/piu-launch.sh` rewritten to use pumptools `piueb` workflow.
  Each version dir must contain: `piu`, `game/`, `lib/`, `hook.so`, `hook.conf`, `piueb`.
  Script links `/opt/pumptools/<hookname>.so → hook.so` and runs `./piueb run`.
- `overlay/opt/bootinsanity/piu-discover.sh` — scans `/mnt/piu/` for `XX_Name/` dirs,
  writes name|path registry to `/var/lib/bootinsanity/piu-versions`.
- `tools/piu-extract-host.sh` — extracts piueb game dir from `.img`/`.img.gz` on HOST
  (needs sudo). Produces `XX_Name/` dir ready for piueb, no image needed at runtime.
- `build.sh` step 4b: pumptools download URL fixed (`latest/pumptools-1.14.zip`, not
  `v1.14/pumptools.zip`). Added missing i386 deps:
  `libxrandr2:i386 libxi6:i386 libxcursor1:i386 libxinerama1:i386 libusb-0.1-4:i386`.
- `Makefile`: added `unexport` of snap-injected library paths (SNAP_LIBRARY_PATH,
  GTK_PATH, etc.) so `make qemu-*` works from snap-hosted VSCode.
- QEMU non-interactive SSH testing approach established: sshpass + PubkeyAuthentication=no.

### Pumptools structure (discovered from 07_Extra image)

Images ship at `/home/pump/Documents/07_extra/` inside the HDD image with:
```
piu          # 32-bit i386 ELF game executable
piueb        # bash launcher (handles LD_PRELOAD + LD_LIBRARY_PATH setup)
hook.so      # pumptools hook (exchook.so for Extra series)
hook.conf    # game config (sound device, sync, patches)
game/        # game assets (428MB for 07_Extra)
lib/         # bundled i386 shared libs (libglfw, libfmodex, libncursesw5, libconfig9)
save/        # eeprom.bin + per-game settings
```

### 07_Extra QEMU test results

| Step | Result |
|---|---|
| pumptools install in VM | ✅ exchook.so, fexhook.so, mk3hook.so, nxhook.so etc. present |
| piueb hook injection | ✅ exchook logging active, eeprom loaded |
| Game binary executes | ✅ `piu` 32-bit process launches, GLFW window created |
| Audio | ⚠️ hw:CARD=Intel,DEV=0 needs `dmix` in hook.conf; ALSA tstamp_type warning |
| Display | ❌ QEMU screendump shows black — game renders via DRM/KMS, not VGA buffer |

**Root cause of black screendump**: X11 with virtio-vga uses modesetting DRM driver.
QEMU `screendump` captures the legacy VGA framebuffer (unused). Need in-guest screenshot
tool (scrot/import) or `sendkey` via monitor to verify visual output.
The game process IS running (11% CPU, Dl/Rl state) — confirmed running, not crashed.

### Remaining pumptools blockers (before commit to main)

1. **Black screendump**: install scrot in image, verify game is actually rendering.
2. **piuio2key.service**: referenced in piu-launch.sh but doesn't exist on bullseye
   (that's the trixie-xlibre service). On bullseye, PIUIO uses the kmod — no service
   to stop. Should gate the stop on service existence.
3. **DISPLAY+XAUTHORITY for root**: piu-launch.sh must set these when called from
   launch.sh (the existing autostart). Add `DISPLAY=:0 XAUTHORITY=...` export.
4. **`xhost +local:`** must be called before piu-launch.sh runs as root.

## Phase 4 — System mode  🟡 COMMITTED, PENDING HARDWARE TEST

Win+F4 escape hatch and Win+key shortcuts are implemented in i3 config +
system-mode scripts. Cannot verify in QEMU: the host window manager intercepts
the Super (Win) key before it reaches the guest.

**Known Win+F4 QEMU limitation**: not a bug — Super key interception is a QEMU
GTK display limitation. Bindings will work on real hardware.

### Hardware test checklist (Phase 4)
- [ ] Win+F4 → drops to desktop (terminal opens with crash log, XSanity killed)
- [ ] Win+Enter → new lxterminal opens
- [ ] Win+V → alsamixer opens in terminal
- [ ] Win+B → system reboots
- [ ] Win+P → system powers off
- [ ] Win+M → pcmanfm opens at /media/pump
- [ ] Win+R → reset-xsanity dialog appears, confirming deletes Save/
- [ ] Win+X → expand-p3 runs (noop if partition already full); df shows correct size
- [ ] 3× XSanity crash → system mode entered automatically (not a hang)

## Phase 5–6 — Updates, polish, Saninet  ⏸ NOT STARTED

Per PLAN.md.

## Post-RC1 Strategy (trixie-xlibre branch)

- **Distro pivot**: Debian 13 (trixie) + 6.x kernel. EOL 2028-06 vs current 2026-08.
- **Simulator**: Xlibre (community GPL StepMania fork). Same Preferences.ini, broader MK series.
- **PIUIO/LXIO**: PIUIO2Key-Linux (userspace pyusb→uinput, Python, maintained) replaces djpohly/piuio kmod.
- **GPU drivers**: Community-packaged legacy 340/390 + official 470 on trixie.
- **usbhid 1ms patch**: Straightforward port to 6.x; hid-core.c unchanged fundamentally.
- **GPU auto-pick**: Pre-built LKM bundles + boot-time lspci detection.
- **MK series**: MVP bullseye MK9 only; trixie branch expands to MK6v2 + MK10.
- **Scout complete**. Awaiting RC1 hardware results; then start trixie phase 0.

## Tested Combinations

| BootInSanity | Debian ISO | XSanity | Host | Status |
|---|---|---|---|---|
| 0.1-phase0 | debian-11.11.0-amd64-DVD-1 | (none) | QEMU | ✅ login prompt |
| 0.1-phase1 | debian-11.11.0-amd64-DVD-1 | 0.96.0 | QEMU | ✅ game launches at 1280x720, kbd + audio + SSH all working |
| 0.2-phase2 | debian-11.11.0-amd64-DVD-1 | 0.96.0 | QEMU | ✅ installer flashes target disk, installed system boots to XSanity persistently |
| —          | —                          | —      | real MK9 | Pending Phase 3 |

## Key Decisions (locked)

- **Distro**: Debian 11 bullseye-LTS. Only LTS shipping all three NVIDIA
  legacy drivers (340 + 390 + 470) needed for stock MK9 GPUs (8400GS,
  9300GS, GT210, GT610, GT710). EOL 2026-08; bookworm migration planned
  post-MVP if 8400GS support no longer required.
- **Branding**: BootInSanity. No Debian/Ubuntu wordmarks. Custom grub +
  plymouth + i3 config.
- **User-supplied inputs**: Debian DVD ISO + XSanity dir. Project never
  redistributes these binaries. Build script consumes them locally.
- **Distribution**: GitHub repo holds build scripts only. No artifact
  hosting. Users build locally.
- **Install model**: Clonezilla-style live ISO that wipes target disk
  and partitions 3 ways: 256M boot + 8G rootfs ro + rest rw. ITG-style
  parity. Phase 2 implements.
- **Audio**: ALSA only. PulseAudio/PipeWire/Wireplumber masked. Lowest
  latency, ITG parity.
- **GPU strategy**: nvidia-340/390/470 official Debian packages. No
  hardware swaps required for any stock MK9 GPU.
- **Build host**: Linux only. Dockerized.
- **Boot mode**: Hybrid BIOS + UEFI on installer ISO.

## Next Concrete Steps

1. User re-tests current ISO (xorg.conf 1280x720 + dual SoundDriver/SoundDevice).
2. If visual still cropped: SSH in, run `xrandr`, see actual modes; iterate.
3. If audio still silent: SSH in, inspect Preferences.ini after XSanity
   wrote it; pick correct key/value; possibly try `SoundDriver=Pulse`.
4. Mark Phase 1 complete once XSanity is fullscreen 1280x720 with audio.
5. Begin Phase 2 — installer wrapper + partition layout.
6. Validate on real MK9 (Phase 3 pre-flight).

## Reproducing the Current State

```bash
git clone <this repo>
cd saniboot
# place debian-11.11.0-amd64-DVD-1.iso in ~/Downloads/
make builder
make iso \
  DEBIAN_ISO=~/Downloads/debian-11.11.0-amd64-DVD-1.iso \
  XSANITY_DIR="/path/to/XSanity 0.96.0/XSanity" \
  VERSION=0.1-phase1
make qemu
```

Resulting ISO at `build/bootinsanity-installer.iso`.

Last build: `bootinsanity-installer.iso` SHA256
`ab64f67d7c3e7cff37bcfebe708e362227fe4af197cccd27791b5a4d8040ae9d`.
