#!/bin/bash
# Pre-extract PIU game tree from a disk image on the HOST.
# Result: <version-dir>/game/ — ready for piu-launch.sh, no image needed at runtime.
#
# Usage: sudo piu-extract-host.sh <image-or-gz> [dest-dir]
#   image-or-gz  path to XX_Name.img or XX_Name.img.gz
#   dest-dir     optional; default: same dir as image, named XX_Name/

set -euo pipefail

IMG_ARG="${1:-}"
[[ -n "$IMG_ARG" ]] || { echo "Usage: $0 <XX_Name.img[.gz]> [dest-dir]" >&2; exit 1; }
[[ "$(id -u)" -eq 0 ]] || { echo "ERROR: run as root (needs losetup + mount)" >&2; exit 1; }

BASE="${IMG_ARG%.img.gz}"
BASE="${BASE%.img}"
NAME="$(basename "$BASE")"
SRCDIR="$(dirname "$BASE")"

DEST_DIR="${2:-${SRCDIR}/${NAME}}"
GAME_DIR="${DEST_DIR}/game"

if [[ -d "$GAME_DIR" ]]; then
    echo "Already extracted: $GAME_DIR"
    exit 0
fi

LOOP_DEV=""
MOUNT_PT="$(mktemp -d)"
OWN_IMG=0

cleanup() {
    set +e
    [[ -n "$LOOP_DEV" ]] && umount "$MOUNT_PT" 2>/dev/null; true
    [[ -n "$LOOP_DEV" ]] && losetup -d "$LOOP_DEV" 2>/dev/null; true
    rmdir "$MOUNT_PT" 2>/dev/null; true
    [[ "$OWN_IMG" -eq 1 ]] && rm -f "${BASE}.img"
}
trap cleanup EXIT

IMG="${BASE}.img"
IMG_GZ="${BASE}.img.gz"

if [[ -f "$IMG" ]]; then
    echo "==> Using pre-decompressed $IMG"
elif [[ -f "$IMG_GZ" ]]; then
    echo "==> Decompressing $IMG_GZ → $IMG"
    zcat "$IMG_GZ" > "$IMG"
    OWN_IMG=1
else
    echo "ERROR: no .img or .img.gz found for $NAME" >&2; exit 1
fi

LOOP_DEV="$(losetup --find --partscan --show "$IMG")"
echo "==> Loop device: $LOOP_DEV"

GAME_PART=""
for part in "${LOOP_DEV}p"*; do
    [[ -b "$part" ]] || continue
    TYPE="$(blkid -o value -s TYPE "$part" 2>/dev/null || true)"
    [[ "$TYPE" == ext2 || "$TYPE" == ext3 || "$TYPE" == ext4 ]] && { GAME_PART="$part"; break; }
done
[[ -n "$GAME_PART" ]] || { echo "ERROR: no ext2/3/4 partition in $IMG" >&2; exit 1; }

echo "==> Mounting $GAME_PART → $MOUNT_PT"
mount -o ro "$GAME_PART" "$MOUNT_PT"

mkdir -p "$GAME_DIR"
echo "==> Copying game tree → $GAME_DIR"
rsync -a --info=progress2 "${MOUNT_PT}/" "${GAME_DIR}/"

umount "$MOUNT_PT"
losetup -d "$LOOP_DEV"; LOOP_DEV=""
rmdir "$MOUNT_PT"
[[ "$OWN_IMG" -eq 1 ]] && { rm -f "$IMG"; OWN_IMG=0; }

trap - EXIT
echo "==> Done: $GAME_DIR"
du -sh "$GAME_DIR"
