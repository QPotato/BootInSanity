#!/bin/bash
# BootInSanity build script — trixie-xlibre branch
#
# Target: Debian 13 (trixie) + 6.x kernel + Xlibre + PIUIO2Key-Linux
#
# Phase 0: bare Debian 13 live ISO bootable in QEMU.
# Phase 1: + X11 + i3 + ALSA + autologin + XSanity/Xlibre injection.
# Phase 2: Clonezilla-style installer, 3-partition install.
# Phase 3: NVIDIA (community packages TBD), usbhid 6.x port, PIUIO2Key-Linux.
# Phase 4: System mode (Win+key shortcuts).
# Phase 5: Update flow + branding polish.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: build.sh [OPTIONS]

Required (interactive prompt if absent and stdin is a TTY):
  --debian-iso PATH       Debian 13 DVD ISO (debian-13.x-amd64-DVD-1.iso)
  --output PATH           Output ISO path

Optional:
  --xsanity-dir PATH      Folder containing XSanity binary + lib/ + assets.
                          If absent, image boots to a "missing XSanity" screen
                          and user supplies XSanity post-install via SCP/USB.
  --version STRING        Version string baked into image (default: dev)
  --gpu TYPE              GPU driver baked in (default: nouveau)
                          Values: nouveau | 340 | 390 | 470
                            nouveau  - in-tree open-source (works for all)
                            340      - legacy 340xx (community pkg, TBD)
                            390      - legacy 390xx (community pkg, TBD)
                            470      - legacy 470xx (community pkg, TBD)
                          Note: only nouveau works on trixie today.
                          Community NVIDIA packages planned; 340/390/470
                          will error until implemented.
  --no-cache              Rebuild chroot from scratch
  --debug                 Drop into chroot shell before ISO-pack
  -h, --help              Show this help
EOF
}

DEBIAN_ISO=""
XSANITY_DIR=""
OUTPUT=""
VERSION="dev"
GPU="nouveau"
NO_CACHE=0
DEBUG=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debian-iso)  DEBIAN_ISO="$2";  shift 2 ;;
        --xsanity-dir) XSANITY_DIR="$2"; shift 2 ;;
        --output)      OUTPUT="$2";      shift 2 ;;
        --version)     VERSION="$2";     shift 2 ;;
        --gpu)         GPU="$2";         shift 2 ;;
        --no-cache)    NO_CACHE=1;       shift ;;
        --debug)       DEBUG=1;          shift ;;
        -h|--help)     usage; exit 0 ;;
        *)             echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

case "$GPU" in
    nouveau|340|390|470) ;;
    *) echo "ERROR: --gpu must be one of: nouveau, 340, 390, 470 (got: $GPU)" >&2; exit 1 ;;
esac

prompt_if_missing() {
    local var="$1" prompt="$2"
    if [[ -z "${!var}" ]] && [[ -t 0 ]]; then
        read -rp "$prompt: " "$var"
    fi
}

prompt_if_missing DEBIAN_ISO "Path to Debian 13 DVD ISO"
prompt_if_missing OUTPUT     "Output ISO path"

[[ -n "$DEBIAN_ISO" ]] || { echo "ERROR: --debian-iso required" >&2; exit 1; }
[[ -n "$OUTPUT"     ]] || { echo "ERROR: --output required"     >&2; exit 1; }
[[ -f "$DEBIAN_ISO" ]] || { echo "ERROR: ISO not found: $DEBIAN_ISO" >&2; exit 1; }

if [[ -n "$XSANITY_DIR" ]]; then
    [[ -d "$XSANITY_DIR" ]] || { echo "ERROR: --xsanity-dir not found: $XSANITY_DIR" >&2; exit 1; }
    [[ -x "$XSANITY_DIR/XSanity"   ]] || { echo "ERROR: $XSANITY_DIR/XSanity not executable" >&2; exit 1; }
    [[ -f "$XSANITY_DIR/XSanity.sh" ]] || { echo "ERROR: $XSANITY_DIR/XSanity.sh not found" >&2; exit 1; }
fi

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: must run as root (use sudo, or 'make iso' which wraps Docker --privileged)" >&2
    exit 1
fi

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
WORK="${ROOT_DIR}/work"
CHROOT="${WORK}/chroot"
ISO_STAGE="${WORK}/iso"
DEBIAN_MNT="${WORK}/debian-iso-mount"
OVERLAY="${ROOT_DIR}/overlay"

mkdir -p "$WORK" "$ISO_STAGE" "$DEBIAN_MNT"

cleanup() {
    set +e
    if mountpoint -q "$DEBIAN_MNT" 2>/dev/null; then
        umount "$DEBIAN_MNT"
    fi
    for m in "${CHROOT}/proc" "${CHROOT}/sys" "${CHROOT}/dev/pts" "${CHROOT}/dev"; do
        if mountpoint -q "$m" 2>/dev/null; then
            umount -l "$m"
        fi
    done
}
trap cleanup EXIT

# Helper: run command inside chroot with /proc /sys /dev bind-mounted.
chroot_run() {
    chroot "$CHROOT" /usr/bin/env -i \
        HOME=/root \
        TERM=xterm \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        DEBIAN_FRONTEND=noninteractive \
        "$@"
}

bind_chroot_mounts() {
    mountpoint -q "${CHROOT}/proc"     || mount -t proc  proc  "${CHROOT}/proc"
    mountpoint -q "${CHROOT}/sys"      || mount -t sysfs sys   "${CHROOT}/sys"
    mountpoint -q "${CHROOT}/dev"      || mount --bind /dev    "${CHROOT}/dev"
    mountpoint -q "${CHROOT}/dev/pts"  || mount --bind /dev/pts "${CHROOT}/dev/pts"
}

echo "==> [1/9] Mounting Debian ISO"
mount -o loop,ro "$DEBIAN_ISO" "$DEBIAN_MNT"
if [[ -f "${DEBIAN_MNT}/.disk/info" ]]; then
    DISK_INFO="$(cat "${DEBIAN_MNT}/.disk/info")"
    echo "    .disk/info: $DISK_INFO"
    if [[ "$DISK_INFO" != *"Debian GNU/Linux 13"* ]]; then
        echo "    WARN: not a Debian 13 ISO (proceeding anyway)" >&2
    fi
else
    echo "    WARN: .disk/info missing — may not be a Debian DVD ISO" >&2
fi

echo "==> [2/9] Building chroot via mmdebstrap"
if [[ "$NO_CACHE" -eq 0 ]] && compgen -G "${CHROOT}/boot/vmlinuz-*" >/dev/null; then
    echo "    Using cached chroot at $CHROOT (--no-cache to rebuild)"
else
    if [[ -d "$CHROOT" ]]; then
        echo "    Cached chroot incomplete or --no-cache set — rebuilding"
    fi
    rm -rf "$CHROOT"
    mkdir -p "$CHROOT"

    # Phase 1 package set: minimal live system + X11 + i3 + ALSA + SSH + NM.
    # Primary: user-supplied DVD-1 (offline-friendly).
    # Fallback: deb.debian.org for packages not on DVD-1.
    INCLUDE=(
        live-boot systemd-sysv linux-image-amd64 initramfs-tools kmod
        console-setup locales sudo bash-completion
        ca-certificates
        # X server + minimal drivers (modesetting works for QEMU virtio-vga
        # and most modern GPUs; nvidia legacy added in Phase 3).
        xserver-xorg-core
        xserver-xorg-input-libinput xserver-xorg-input-evdev
        xserver-xorg-video-modesetting xserver-xorg-video-fbdev xserver-xorg-video-vesa
        xinit xauth xterm dbus-x11 x11-xserver-utils
        # Window manager
        i3 i3-wm
        # Audio (ALSA only — no PulseAudio/PipeWire for lowest latency)
        alsa-utils libasound2-plugins
        # Networking + time
        network-manager chrony
        # Remote management
        openssh-server
        # Terminal for missing-xsanity screen + system mode
        lxterminal
        # Fonts (i3 + xterm need at least one font)
        fonts-dejavu-core xfonts-base
        # Mesa userland (OpenGL) — XSanity links against libGL
        libgl1-mesa-dri libgl1
        # Phase 2 installer: partition / format / unsquashfs / GRUB
        parted squashfs-tools dosfstools e2fsprogs rsync util-linux
        grub-pc-bin grub-efi-amd64-bin grub2-common grub-common
        os-prober
        # loop-mount + extraction for PIU .img.gz images
        mount util-linux
        # Python + evdev + usb for PIUIO2Key-Linux and launcher UI
        python3 python3-evdev python3-usb python3-pygame
        # unzip: needed by pumptools extraction step
        unzip
        # Phase 4 system mode
        pcmanfm evtest cloud-guest-utils
        # curl for pumptools download at build time (wget as fallback)
        curl
        # 32-bit compat layer (pure amd64 packages; :i386 libs installed in step 4b
        # after dpkg --add-architecture i386 + apt-get update)
        libc6-i386 lib32stdc++6
    )
    case "$GPU" in
        nouveau) ;;  # in-tree modesetting; no extra packages
        340|390|470)
            # Community NVIDIA legacy packages for trixie not yet implemented.
            # Will be added when community repos are set up (see PLAN.md trixie section).
            echo "ERROR: GPU=$GPU not yet supported on trixie. Use GPU=nouveau." >&2
            exit 1
            ;;
    esac
    INCLUDE_CSV=$(IFS=,; echo "${INCLUDE[*]}")

    # non-free-firmware is a separate component in trixie (split from non-free in bookworm).
    mmdebstrap \
        --variant=minbase \
        --architectures=amd64 \
        --components=main,contrib,non-free,non-free-firmware \
        --include="$INCLUDE_CSV" \
        trixie \
        "$CHROOT" \
        "deb [trusted=yes] copy://${DEBIAN_MNT} trixie main contrib" \
        "deb [trusted=yes] http://deb.debian.org/debian trixie main contrib non-free non-free-firmware"
fi

echo "==> [3/9] Applying rootfs overlay"
if [[ -d "$OVERLAY" ]]; then
    rsync -a "${OVERLAY}/" "${CHROOT}/"
    # Overlay files are copied with host-side UIDs. Reset system paths to
    # root:root (sudo refuses /etc/sudoers.d unless root-owned). Home dirs
    # get pump:pump after user creation in step [4/9].
    chown -R 0:0 "${CHROOT}/etc" "${CHROOT}/opt"
    chmod 0755 "${CHROOT}/opt/bootinsanity/"*.sh
    chmod 0755 "${CHROOT}/opt/bootinsanity/system-mode/"*.sh 2>/dev/null || true
    chmod 0755 "${CHROOT}/opt/bootinsanity-installer/"*.sh 2>/dev/null || true
    chmod 0440 "${CHROOT}/etc/sudoers.d/pump"
else
    echo "    WARN: overlay/ directory missing — skipping" >&2
fi

# Replace mmdebstrap's apt sources (which include host-only copy:// paths)
# with network-only sources usable from inside the chroot at build time
# AND on the installed system at runtime.
cat > "${CHROOT}/etc/apt/sources.list" <<'EOF'
deb http://deb.debian.org/debian               trixie           main contrib non-free non-free-firmware
deb http://deb.debian.org/debian               trixie-updates   main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security  main contrib non-free non-free-firmware
EOF

# Bake hostname + version banner.
echo "bootinsanity" > "${CHROOT}/etc/hostname"
cat > "${CHROOT}/etc/issue" <<EOF
BootInSanity ${VERSION} \\n \\l

EOF
echo "BootInSanity ${VERSION}" > "${CHROOT}/etc/bootinsanity-version"
cat > "${CHROOT}/etc/hosts" <<'EOF'
127.0.0.1   localhost
127.0.1.1   bootinsanity
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF

echo "==> [4/9] Configuring system inside chroot"
bind_chroot_mounts

# Create pump user (idempotent).
if ! chroot_run getent passwd pump >/dev/null; then
    chroot_run useradd -m -s /bin/bash -G sudo,audio,video,input,plugdev,dialout pump
    chroot_run bash -c 'echo "pump:pump" | chpasswd'
fi
# Lock root login (defense-in-depth; pump has sudo).
chroot_run passwd -l root

# Re-own pump home after overlay.
chroot_run chown -R pump:pump /home/pump

# Enable services.
chroot_run systemctl enable ssh.service
chroot_run systemctl enable NetworkManager.service
chroot_run systemctl enable chrony.service
chroot_run systemctl enable getty@tty1.service
chroot_run systemctl enable bootinsanity-installer.service
chroot_run systemctl enable piuio2key.service

# Mask audio servers we are NOT using (ALSA only).
for svc in pulseaudio.service pulseaudio.socket pipewire.service pipewire.socket \
           pipewire-pulse.service pipewire-pulse.socket wireplumber.service; do
    chroot_run systemctl mask "$svc" 2>/dev/null || true
done

# Locale: en_US.UTF-8.
chroot_run sed -i 's/^# *en_US\.UTF-8/en_US.UTF-8/' /etc/locale.gen
chroot_run locale-gen
chroot_run update-locale LANG=en_US.UTF-8

echo "==> [4b/9] Installing pumptools (PIU legacy game compatibility layer)"
PUMPTOOLS_VER="1.14"
PUMPTOOLS_URL="https://github.com/pumpitupdev/pumptools/releases/download/latest/pumptools-${PUMPTOOLS_VER}.zip"
PUMPTOOLS_DEST="${CHROOT}/opt/pumptools"
mkdir -p "$PUMPTOOLS_DEST"

# Enable i386 multiarch so 32-bit pumptools hooks + game binaries can run.
chroot_run dpkg --add-architecture i386
chroot_run apt-get update -qq
chroot_run apt-get install -y --no-install-recommends \
    libc6-i386 lib32stdc++6 \
    libx11-6:i386 libasound2:i386 \
    libxrandr2:i386 libxi6:i386 libxcursor1:i386 libxinerama1:i386 \
    libgl1-mesa-dri:i386 libglu1-mesa:i386 \
    libcurl4:i386 libusb-0.1-4:i386 || true

# Download pumptools prebuilt release into chroot.
if curl -fsSL --max-time 120 -o "${PUMPTOOLS_DEST}/pumptools.zip" "$PUMPTOOLS_URL"; then
    # Outer zip extracts hook zips + piueb + docs. Unzip each hook zip so
    # exchook.so, fexhook.so etc. land flat in /opt/pumptools/.
    chroot_run bash -c "cd /opt/pumptools && unzip -qo pumptools.zip && rm pumptools.zip && \
        for z in *.zip; do unzip -qo \"\$z\"; done && rm -f *.zip"
    echo "    pumptools v${PUMPTOOLS_VER} installed at /opt/pumptools"
else
    echo "    WARN: pumptools download failed — PIU launch will not work" >&2
    echo "    URL tried: $PUMPTOOLS_URL" >&2
fi

echo "==> [4b-2/9] Installing PIUIO2Key-Linux"
PIUIO2KEY_URL="https://github.com/carlos-garcia/PIUIO2Key-Linux/archive/refs/heads/main.zip"
PIUIO2KEY_DEST="${CHROOT}/opt/bootinsanity/piuio2key"
mkdir -p "$PIUIO2KEY_DEST"
if curl -fsSL --max-time 60 -o /tmp/piuio2key.zip "$PIUIO2KEY_URL"; then
    unzip -q /tmp/piuio2key.zip -d /tmp/piuio2key-extract
    # Archive root is PIUIO2Key-Linux-main/
    rsync -a /tmp/piuio2key-extract/PIUIO2Key-Linux-main/ "$PIUIO2KEY_DEST/"
    rm -rf /tmp/piuio2key.zip /tmp/piuio2key-extract
    chroot_run chown -R root:root /opt/bootinsanity/piuio2key
    chroot_run chmod +x /opt/bootinsanity/piuio2key/piu_bridge.py
    echo "    PIUIO2Key-Linux installed at /opt/bootinsanity/piuio2key"
else
    echo "    WARN: PIUIO2Key-Linux download failed — PIUIO USB bridge will not work" >&2
    echo "    URL tried: $PIUIO2KEY_URL" >&2
fi

echo "==> [4c/9] Building out-of-tree kernel modules"
KVER_CHROOT="$(ls -1 "${CHROOT}/boot/" | grep '^vmlinuz-' | sort -V | tail -1 | sed 's|^vmlinuz-||')"
KMAJ="${KVER_CHROOT%%.*}"
if [[ "$KMAJ" -le 5 ]]; then
    # 5.x path: usbhid 1ms patch + piuio kmod (bullseye/bookworm).
    PATCH_SRC="${ROOT_DIR}/kernel/usbhid-1ms.patch"
    BUILDER_SRC="${ROOT_DIR}/kernel/build-kmods.sh"
    if [[ -f "$PATCH_SRC" ]] && [[ -f "$BUILDER_SRC" ]]; then
        cp "$PATCH_SRC"   "${CHROOT}/tmp/usbhid-1ms.patch"
        cp "$BUILDER_SRC" "${CHROOT}/tmp/build-kmods.sh"
        chmod +x "${CHROOT}/tmp/build-kmods.sh"
        chroot_run /tmp/build-kmods.sh
        rm -f "${CHROOT}/tmp/usbhid-1ms.patch" "${CHROOT}/tmp/build-kmods.sh"
    else
        echo "    WARN: kernel/build-kmods.sh missing — skipping" >&2
    fi
else
    # 6.x path: usbhid 1ms patch only (piuio replaced by PIUIO2Key-Linux userspace).
    PATCH_PY="${ROOT_DIR}/kernel/patch-usbhid.py"
    BUILDER_6X="${ROOT_DIR}/kernel/build-kmods-6x.sh"
    if [[ -f "$PATCH_PY" ]] && [[ -f "$BUILDER_6X" ]]; then
        cp "$PATCH_PY"    "${CHROOT}/tmp/patch-usbhid.py"
        cp "$BUILDER_6X"  "${CHROOT}/tmp/build-kmods-6x.sh"
        chmod +x "${CHROOT}/tmp/build-kmods-6x.sh"
        chroot_run /tmp/build-kmods-6x.sh
        rm -f "${CHROOT}/tmp/patch-usbhid.py" "${CHROOT}/tmp/build-kmods-6x.sh"
    else
        echo "    WARN: kernel/build-kmods-6x.sh or patch-usbhid.py missing — skipping" >&2
    fi
fi

echo "==> [5/9] Injecting XSanity"
if [[ -n "$XSANITY_DIR" ]]; then
    echo "    Copying $XSANITY_DIR → /mnt/xsanity/"
    mkdir -p "${CHROOT}/mnt/xsanity"
    rsync -a "${XSANITY_DIR%/}/" "${CHROOT}/mnt/xsanity/"
    chroot_run chown -R pump:pump /mnt/xsanity
    chmod +x "${CHROOT}/mnt/xsanity/XSanity.sh" 2>/dev/null || true

    # XSanity bundles glibc 2.42 (libc.so.6, libm.so.6, libmvec.so.1, ld-linux)
    # but does NOT ship libpthread.so.0, libdl.so.2, librt.so.1, libresolv.so.2.
    # In glibc 2.34+ these are empty stubs (symbols merged into libc itself).
    # On a Debian 11 host (glibc 2.31), system libpthread.so.0 gets loaded and
    # tries to link to the bundled libc 2.42 → GLIBC_PRIVATE symbol mismatch
    # (e.g. __libc_pthread_init undefined). Fix: symlink the missing stubs to
    # bundled libc.so.6 so the bundled libc serves the merged symbols.
    XLIB="${CHROOT}/mnt/xsanity/lib"
    if [[ -d "$XLIB" ]]; then
        for stub in libpthread.so.0 libdl.so.2 librt.so.1 libresolv.so.2 libutil.so.1; do
            if [[ ! -e "${XLIB}/${stub}" ]]; then
                ln -s libc.so.6 "${XLIB}/${stub}"
                echo "    Created stub symlink: lib/${stub} -> libc.so.6"
            fi
        done
    fi
else
    echo "    No --xsanity-dir given. Image will boot to 'missing XSanity' screen."
    mkdir -p "${CHROOT}/mnt/xsanity"
fi

if [[ "$DEBUG" -eq 1 ]]; then
    echo "==> Debug requested — entering chroot. Exit shell to continue."
    chroot_run /bin/bash || true
fi

# Unmount chroot binds before squashing.
cleanup
mkdir -p "$DEBIAN_MNT"
mount -o loop,ro "$DEBIAN_ISO" "$DEBIAN_MNT"  # remount for any later steps

echo "==> [6/9] Building squashfs"
mkdir -p "${ISO_STAGE}/live"
rm -f "${ISO_STAGE}/live/filesystem.squashfs"
# Note: do NOT exclude /boot — Phase 2 installer extracts the squashfs onto
# the target disk, and the installed system needs kernel + initrd + grub
# config under /boot. The kernel/initrd are duplicated into /live/ on the
# ISO for live-boot, but that's only used for the installer's runtime
# environment.
mksquashfs "$CHROOT" "${ISO_STAGE}/live/filesystem.squashfs" \
    -comp xz -noappend

echo "==> [7/9] Copying kernel + initrd"
KVER="$(ls -1 "${CHROOT}/boot/" | grep '^vmlinuz-' | sort -V | tail -1 | sed 's|^vmlinuz-||')"
[[ -n "$KVER" ]] || { echo "ERROR: no kernel found in chroot" >&2; exit 1; }
echo "    kernel version: $KVER"
cp "${CHROOT}/boot/vmlinuz-${KVER}"   "${ISO_STAGE}/live/vmlinuz"
cp "${CHROOT}/boot/initrd.img-${KVER}" "${ISO_STAGE}/live/initrd"

echo "==> [8/9] Writing bootloaders (BIOS via isolinux, UEFI via grub)"

# BIOS: isolinux
mkdir -p "${ISO_STAGE}/isolinux"
cp /usr/lib/ISOLINUX/isolinux.bin                     "${ISO_STAGE}/isolinux/"
cp /usr/lib/syslinux/modules/bios/ldlinux.c32         "${ISO_STAGE}/isolinux/"
cp /usr/lib/syslinux/modules/bios/libcom32.c32        "${ISO_STAGE}/isolinux/"
cp /usr/lib/syslinux/modules/bios/libutil.c32         "${ISO_STAGE}/isolinux/"
cp /usr/lib/syslinux/modules/bios/menu.c32            "${ISO_STAGE}/isolinux/"
cp /usr/lib/syslinux/modules/bios/vesamenu.c32        "${ISO_STAGE}/isolinux/"

cat > "${ISO_STAGE}/isolinux/isolinux.cfg" <<EOF
UI menu.c32
PROMPT 0
TIMEOUT 100
DEFAULT clean
MENU TITLE BootInSanity Installer (${VERSION})

LABEL clean
  MENU LABEL Clean Install (wipes target disk)
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live install=clean quiet

LABEL update
  MENU LABEL Update (re-flash rootfs, preserve XSanity + Songs)
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live install=update quiet

LABEL live
  MENU LABEL Live Boot (no install — play from USB only)
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live quiet
EOF

# UEFI: grub
mkdir -p "${ISO_STAGE}/EFI/boot" "${ISO_STAGE}/boot/grub"
cat > "${ISO_STAGE}/boot/grub/grub.cfg" <<EOF
set timeout=10
set default=0

menuentry "BootInSanity — Clean Install (wipes target disk)" {
    linux  /live/vmlinuz boot=live install=clean quiet
    initrd /live/initrd
}

menuentry "BootInSanity — Update (re-flash rootfs, preserve XSanity + Songs)" {
    linux  /live/vmlinuz boot=live install=update quiet
    initrd /live/initrd
}

menuentry "BootInSanity — Live Boot (no install)" {
    linux  /live/vmlinuz boot=live quiet
    initrd /live/initrd
}
EOF

grub-mkstandalone \
    --format=x86_64-efi \
    --output="${ISO_STAGE}/EFI/boot/bootx64.efi" \
    --locales="" --fonts="" \
    "boot/grub/grub.cfg=${ISO_STAGE}/boot/grub/grub.cfg"

EFI_IMG="${ISO_STAGE}/boot/grub/efi.img"
dd if=/dev/zero of="$EFI_IMG" bs=1M count=10 status=none
mkfs.vfat -n EFI "$EFI_IMG" >/dev/null
mmd  -i "$EFI_IMG" ::/EFI ::/EFI/boot
mcopy -i "$EFI_IMG" "${ISO_STAGE}/EFI/boot/bootx64.efi" ::/EFI/boot/

echo "==> [9/9] Assembling hybrid BIOS+EFI ISO"
mkdir -p "$(dirname "$OUTPUT")"
xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "BOOTINSANITY_LIVE" \
    -eltorito-boot isolinux/isolinux.bin \
    -eltorito-catalog isolinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    --eltorito-alt-boot \
    -e boot/grub/efi.img \
    -no-emul-boot \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -isohybrid-gpt-basdat \
    -output "$OUTPUT" \
    "$ISO_STAGE"

echo ""
echo "==> Done."
echo "    Output: $OUTPUT"
echo "    Size:   $(du -h "$OUTPUT" | cut -f1)"
echo "    SHA256: $(sha256sum "$OUTPUT" | awk '{print $1}')"
