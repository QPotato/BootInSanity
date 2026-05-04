#!/bin/bash
# BootInSanity installer.
# Triggered by systemd bootinsanity-installer.service when /proc/cmdline contains
# install=clean or install=update.
#
# clean   - wipe target disk, partition fresh, full install (incl. XSanity p3)
# update  - re-flash rootfs (p2) only; preserve p1 + p3 (user XSanity + Songs)

set -euo pipefail

LOG=/var/log/bootinsanity-install.log
exec > >(tee -a "$LOG") 2>&1

err() { echo "ERROR: $*" >&2; }
banner() {
    clear
    cat <<EOF

  ============================================================
                    BootInSanity Installer
                    Version: ${VERSION:-unknown}  GPU: ${GPU:-unknown}
                    Mode: $MODE
  ============================================================

EOF
}

MODE=$(grep -oE 'install=[a-z]+' /proc/cmdline | head -1 | cut -d= -f2 || true)
[[ -n "${MODE:-}" ]] || { err "install= not in /proc/cmdline"; exit 1; }
[[ "$MODE" == "clean" || "$MODE" == "update" ]] || { err "invalid mode: $MODE"; exit 1; }

# Read version from ISO root metadata file.
META=/run/live/medium/bootinsanity.meta
VERSION=$(grep '^VERSION=' "$META" 2>/dev/null | cut -d= -f2 || echo "unknown")
GPU=$(grep '^GPU=' "$META" 2>/dev/null | cut -d= -f2 || echo "unknown")

banner

# -------------------------------------------------------------------------
# Detect target disk
# -------------------------------------------------------------------------
LIVE_SRC=$(findmnt -no SOURCE /run/live/medium 2>/dev/null || true)
LIVE_DISK=""
if [[ -n "$LIVE_SRC" ]]; then
    LIVE_DISK=$(lsblk -no PKNAME "$LIVE_SRC" 2>/dev/null || true)
fi

mapfile -t TARGETS < <(
    lsblk -dn -o NAME,TYPE,SIZE,MODEL | awk '$2=="disk"{print $0}' \
        | while read -r name type size model; do
            [[ "$name" == "$LIVE_DISK" ]] && continue
            # Skip floppies, CD-ROMs, ramdisks, loop devices, zram
            case "$name" in
                fd*|sr*|loop*|ram*|zram*) continue ;;
            esac
            # Skip disks smaller than 4 GB (sanity guard against fake/tiny devices)
            size_bytes=$(blockdev --getsize64 "/dev/$name" 2>/dev/null || echo 0)
            (( size_bytes >= 4 * 1024 * 1024 * 1024 )) || continue
            echo "$name $size $model"
        done
)

if [[ ${#TARGETS[@]} -eq 0 ]]; then
    err "No target disks detected (live medium: ${LIVE_DISK:-unknown})"
    read -rp "Press Enter to reboot..."
    reboot; exit 0
fi

if [[ ${#TARGETS[@]} -eq 1 ]]; then
    TARGET_NAME=$(awk '{print $1}' <<<"${TARGETS[0]}")
    echo "Auto-selected target: ${TARGETS[0]}"
else
    echo "Multiple disks detected:"
    i=1
    for t in "${TARGETS[@]}"; do
        echo "  $i) $t"
        i=$((i+1))
    done
    while :; do
        read -rp "Pick target [1-${#TARGETS[@]}]: " sel
        [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#TARGETS[@]} )) && break
    done
    TARGET_NAME=$(awk '{print $1}' <<<"${TARGETS[$((sel-1))]}")
fi

TARGET="/dev/$TARGET_NAME"
SIZE_BYTES=$(blockdev --getsize64 "$TARGET")
SIZE_GB=$((SIZE_BYTES / 1024 / 1024 / 1024))

# Partition device naming: nvme0n1p1 vs sda1
case "$TARGET_NAME" in
    nvme*|mmcblk*|loop*) P1="${TARGET}p1"; P2="${TARGET}p2"; P3="${TARGET}p3" ;;
    *)                   P1="${TARGET}1";  P2="${TARGET}2";  P3="${TARGET}3"  ;;
esac

cat <<EOF

  Target disk:  $TARGET ($SIZE_GB GB)
  Partitions:   $P1 (boot 256M), $P2 (rootfs 8G), $P3 (data, fills disk)

EOF

if [[ "$MODE" == "clean" ]]; then
    echo "  WARNING: ALL DATA on $TARGET will be ERASED."
else
    echo "  Update mode: ONLY $P2 (rootfs) will be re-flashed."
    echo "  $P1 (boot) and $P3 (XSanity + Songs) will be preserved."
fi

read -rp "Type YES to confirm: " confirm
[[ "$confirm" == "YES" ]] || { echo "Aborted."; sleep 2; exit 1; }

# -------------------------------------------------------------------------
# Partition + format
# -------------------------------------------------------------------------
if [[ "$MODE" == "clean" ]]; then
    echo
    echo "==> Partitioning $TARGET (msdos, 3 partitions)"
    parted -s "$TARGET" mklabel msdos
    parted -s "$TARGET" mkpart primary fat32 1MiB     257MiB
    parted -s "$TARGET" set 1 boot on
    parted -s "$TARGET" mkpart primary ext4  257MiB   8449MiB
    parted -s "$TARGET" mkpart primary ext4  8449MiB  100%
    sleep 1
    partprobe "$TARGET" 2>/dev/null || true
    sleep 1

    echo "==> Formatting partitions"
    mkfs.vfat -n SP_BOOT "$P1"
    mkfs.ext4 -F -L sp-root "$P2"
    mkfs.ext4 -F -L sp-data "$P3"
else
    # Update mode: only re-make p2.
    [[ -b "$P1" && -b "$P2" && -b "$P3" ]] || {
        err "Update mode requires existing 3-partition layout on $TARGET"
        exit 1
    }
    echo "==> Re-formatting $P2 only (rootfs)"
    mkfs.ext4 -F -L sp-root "$P2"
fi

# -------------------------------------------------------------------------
# Mount + restore rootfs
# -------------------------------------------------------------------------
MNT=/mnt/install-target
mkdir -p "$MNT"
mount "$P2" "$MNT"

SQUASHFS=/run/live/medium/live/filesystem.squashfs
[[ -f "$SQUASHFS" ]] || { err "squashfs not found at $SQUASHFS"; exit 1; }

# XSanity lives in the squashfs at mnt/xsanity/ for live-boot, but must land
# on p3 (sp-data) for the installed system. p2 (8 GB) cannot hold both rootfs
# and XSanity, so we exclude mnt/xsanity from the p2 extraction and write it
# directly to p3 (clean install) or leave p3 untouched (update).
#
# unsquashfs -excludes SQUASHFS PATTERN... excludes matching paths.

echo "==> Extracting rootfs to $P2 (excluding XSanity)"
unsquashfs -f -d "$MNT" -excludes "$SQUASHFS" "mnt/xsanity"
mkdir -p "$MNT/mnt/xsanity"   # mount point for p3

if [[ "$MODE" == "clean" ]]; then
    echo "==> Extracting XSanity to $P3"
    SP_DATA=/mnt/sp-data
    mkdir -p "$SP_DATA"
    mount "$P3" "$SP_DATA"

    # Extract with path prefix mnt/xsanity/ into p3, then mv contents to p3
    # root (same filesystem → mv is O(1), no data copy).
    unsquashfs -f -d "$SP_DATA" "$SQUASHFS" "mnt/xsanity"
    if [[ -d "$SP_DATA/mnt/xsanity" ]]; then
        find "$SP_DATA/mnt/xsanity" -maxdepth 1 -mindepth 1 \
            -exec mv -t "$SP_DATA" {} +
        rmdir "$SP_DATA/mnt/xsanity" "$SP_DATA/mnt" 2>/dev/null || true
    fi

    umount "$SP_DATA"
    rmdir "$SP_DATA" 2>/dev/null || true
else
    echo "    Update mode: $P3 (XSanity + Songs) untouched."
fi

# Mount p1 ESP for grub-install
mkdir -p "$MNT/boot/efi"
mount "$P1" "$MNT/boot/efi"

# -------------------------------------------------------------------------
# fstab with fresh UUIDs
# -------------------------------------------------------------------------
echo "==> Writing fstab"
P1_UUID=$(blkid -s UUID -o value "$P1")
P2_UUID=$(blkid -s UUID -o value "$P2")
P3_UUID=$(blkid -s UUID -o value "$P3")
cat > "$MNT/etc/fstab" <<EOF
# BootInSanity fstab — generated by installer on $(date -Iseconds)
UUID=$P2_UUID  /             ext4  defaults,noatime          0 1
UUID=$P1_UUID  /boot/efi     vfat  defaults,umask=0077       0 2
UUID=$P3_UUID  /mnt/xsanity  ext4  defaults,noatime          0 2
tmpfs          /tmp          tmpfs defaults,nosuid,nodev     0 0
EOF

# -------------------------------------------------------------------------
# GRUB hybrid (BIOS + UEFI)
# -------------------------------------------------------------------------
echo "==> Installing GRUB"
for d in proc sys dev dev/pts; do
    mount --bind "/$d" "$MNT/$d"
done
trap 'for d in dev/pts dev sys proc; do umount "$MNT/$d" 2>/dev/null || true; done' EXIT

# BIOS GRUB to MBR
chroot "$MNT" grub-install --target=i386-pc --boot-directory=/boot \
    --recheck "$TARGET"

# UEFI GRUB to ESP (--removable so it boots without firmware NVRAM entry,
# matching ITG-style "any-machine-installable" kiosk image)
chroot "$MNT" grub-install --target=x86_64-efi --efi-directory=/boot/efi \
    --bootloader-id=bootinsanity --boot-directory=/boot --removable --recheck

chroot "$MNT" update-grub

# -------------------------------------------------------------------------
# Cleanup + reboot
# -------------------------------------------------------------------------
sync
trap - EXIT
for d in dev/pts dev sys proc; do
    umount "$MNT/$d" 2>/dev/null || true
done
umount "$MNT/boot/efi"
umount "$MNT"

cat <<EOF

  ============================================================
                  Installation complete.
  ============================================================

  Rebooting in 10 seconds. Remove install medium when system
  starts powering off.

EOF
sleep 10
reboot
