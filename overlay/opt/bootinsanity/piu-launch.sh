#!/bin/bash
# Launch a PIU legacy game version via pumptools piueb.
# Usage: piu-launch.sh <version-dir>
#   version-dir: path to directory named XX_Name (e.g. /mnt/piu/07_Extra)
#                Must contain piueb + piu + game/ + lib/ + hook.so + hook.conf.
#                If absent, first-run extraction from XX_Name.img[.gz] is attempted.
#
# Hook source: /opt/pumptools/<hookname>.so — see HOOK_MAP below.
# IO mode: controlled by hook.conf. Default (generated): keyboard (QEMU-safe).

set -euo pipefail

PUMPTOOLS=/opt/pumptools
PIUIO2KEY_SVC=piuio2key.service

VERSION_DIR="${1:-}"
[[ -n "$VERSION_DIR" ]] || { echo "Usage: $0 <version-dir>" >&2; exit 1; }

VERSION_NAME="$(basename "$VERSION_DIR")"
IMG_GZ="$(dirname "$VERSION_DIR")/${VERSION_NAME}.img.gz"
IMG="${IMG_GZ%.img.gz}.img"

# ---------------------------------------------------------------------------
# Hook selection — map version name prefix to pumptools hook .so
# ---------------------------------------------------------------------------
declare -A HOOK_MAP=(
    ["07"]="exchook"
    ["08"]="exchook"
    ["09"]="exchook"
    ["10"]="exchook"
    ["11"]="mk3hook"
    ["12"]="mk3hook"
    ["13"]="mk3hook"
    ["20"]="nxhook"
    ["21"]="nxahook"
    ["22"]="nx2hook"
    ["23"]="prohook"
    ["24"]="pro2hook"
    ["25"]="fexhook"
    ["26"]="primehook"
)

PREFIX="${VERSION_NAME:0:2}"
HOOK_NAME="${HOOK_MAP[$PREFIX]:-}"

[[ -n "$HOOK_NAME" ]] || {
    echo "ERROR: no hook mapping for version prefix '$PREFIX' in $VERSION_NAME" >&2
    echo "       Create ${VERSION_DIR}/hook.so manually (symlink to the right pumptools .so)" >&2
    exit 1
}

HOOK_SO="${PUMPTOOLS}/${HOOK_NAME}.so"
[[ -f "$HOOK_SO" ]] || {
    echo "ERROR: pumptools hook not found: $HOOK_SO" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# First-run extraction: rsync piueb game dir from disk image
# ---------------------------------------------------------------------------
if [[ ! -f "${VERSION_DIR}/piu" ]]; then
    [[ -f "$IMG" || -f "$IMG_GZ" ]] || {
        echo "ERROR: no game dir, no .img, no .img.gz for $VERSION_NAME" >&2; exit 1
    }

    echo "==> First run: extracting $VERSION_NAME from disk image..."

    LOOP_DEV=""
    MOUNT_PT="$(mktemp -d)"
    OWN_IMG=0
    cleanup_extract() {
        set +e
        [[ -n "$LOOP_DEV" ]] && umount "$MOUNT_PT" 2>/dev/null; true
        [[ -n "$LOOP_DEV" ]] && losetup -d "$LOOP_DEV" 2>/dev/null; true
        rmdir "$MOUNT_PT" 2>/dev/null; true
        [[ "$OWN_IMG" -eq 1 ]] && rm -f "$IMG"
    }
    trap cleanup_extract EXIT

    if [[ ! -f "$IMG" ]]; then
        echo "    Decompressing $IMG_GZ → $IMG"
        zcat "$IMG_GZ" > "$IMG"
        OWN_IMG=1
    fi

    LOOP_DEV="$(losetup --find --partscan --show "$IMG")"
    echo "    Loop device: $LOOP_DEV"

    GAME_PART=""
    for part in "${LOOP_DEV}p"*; do
        [[ -b "$part" ]] || continue
        TYPE="$(blkid -o value -s TYPE "$part" 2>/dev/null || true)"
        [[ "$TYPE" == ext2 || "$TYPE" == ext3 || "$TYPE" == ext4 ]] && { GAME_PART="$part"; break; }
    done
    [[ -n "$GAME_PART" ]] || { echo "ERROR: no ext2/3/4 partition in $IMG" >&2; exit 1; }

    mount -o ro,noload "$GAME_PART" "$MOUNT_PT"

    # Find the piueb launcher inside the image to locate the game dir
    PIUEB_IN_IMG="$(find "$MOUNT_PT" -name 'piueb' -maxdepth 6 2>/dev/null | head -1)"
    [[ -n "$PIUEB_IN_IMG" ]] || { echo "ERROR: piueb not found in image" >&2; exit 1; }
    GAME_SRC="$(dirname "$PIUEB_IN_IMG")"

    echo "    Found game dir: $GAME_SRC"
    mkdir -p "$VERSION_DIR"
    rsync -a --no-owner --no-group --info=progress2 "${GAME_SRC}/" "${VERSION_DIR}/"

    umount "$MOUNT_PT"; LOOP_DEV=""
    rmdir "$MOUNT_PT"
    trap - EXIT
    echo "    Extraction complete."
fi

# ---------------------------------------------------------------------------
# Ensure hook.so points to our pumptools build
# ---------------------------------------------------------------------------
HOOK_DEST="${VERSION_DIR}/hook.so"
# Replace with symlink to our pumptools hook if absent or stale
if [[ ! -L "$HOOK_DEST" ]] || [[ "$(readlink "$HOOK_DEST")" != "$HOOK_SO" ]]; then
    ln -sf "$HOOK_SO" "$HOOK_DEST"
    echo "==> Linked ${HOOK_NAME}.so → hook.so"
fi

# Ensure piueb is present (may not be in images that predate the piueb workflow)
if [[ ! -f "${VERSION_DIR}/piueb" ]]; then
    cp "$PUMPTOOLS/piueb" "${VERSION_DIR}/piueb"
    chmod +x "${VERSION_DIR}/piueb"
fi

# ---------------------------------------------------------------------------
# Stop PIUIO2Key-Linux — pumptools owns IO from here
# ---------------------------------------------------------------------------
PIUIO2KEY_WAS_RUNNING=0
if systemctl is-active --quiet "$PIUIO2KEY_SVC" 2>/dev/null; then
    echo "==> Stopping $PIUIO2KEY_SVC (pumptools takes IO ownership)"
    systemctl stop "$PIUIO2KEY_SVC"
    PIUIO2KEY_WAS_RUNNING=1
fi

restart_piuio2key() {
    [[ "$PIUIO2KEY_WAS_RUNNING" -eq 1 ]] && systemctl start "$PIUIO2KEY_SVC" || true
}
trap restart_piuio2key EXIT

# ---------------------------------------------------------------------------
# Launch via piueb (must run as root — piueb enforces this)
# ---------------------------------------------------------------------------
echo "==> Launching $VERSION_NAME (hook: ${HOOK_NAME})"
cd "$VERSION_DIR"
exec ./piueb run
