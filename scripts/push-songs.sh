#!/bin/bash
# Push XSanity content from a local directory to the arcade.
# Songs/SongMovies/Avatars/NoteSkins: always overwrite (step charts get updated).
# Save/: keep most recent version of each file (--update).
#
# Usage:
#   ./scripts/push-songs.sh <source-dir> [arcade-ip]
#
# Examples:
#   ./scripts/push-songs.sh ~/XSanity
#   ./scripts/push-songs.sh ~/XSanity 192.168.100.2
#
# Expects SSH key auth to pump@<arcade-ip>. Default IP: 192.168.100.2.

set -euo pipefail

SRC="${1:?Usage: $0 <source-dir> [arcade-ip]}"
ARCADE="${2:-192.168.100.2}"
DEST_BASE="pump@${ARCADE}:/mnt/xsanity"

if [[ ! -d "$SRC" ]]; then
    echo "ERROR: $SRC is not a directory" >&2
    exit 1
fi

# Determine what to push
OVERWRITE_DIRS=()
for dir in Songs SongMovies Avatars NoteSkins; do
    if [[ -d "$SRC/$dir" ]]; then
        OVERWRITE_DIRS+=("$dir")
    elif [[ "$(basename "$SRC")" == "$dir" ]]; then
        # User passed the Songs/ dir directly rather than its parent
        OVERWRITE_DIRS+=("$dir")
        SRC="$(dirname "$SRC")"
    fi
done
HAS_SAVE=0
[[ -d "$SRC/Save" ]] && HAS_SAVE=1

if [[ ${#OVERWRITE_DIRS[@]} -eq 0 && "$HAS_SAVE" -eq 0 ]]; then
    echo "ERROR: $SRC contains none of: Songs/ SongMovies/ Avatars/ NoteSkins/ Save/" >&2
    exit 1
fi

echo "Arcade : $ARCADE"
echo "Source : $SRC"
for dir in "${OVERWRITE_DIRS[@]}"; do echo "  → $dir/ (overwrite)"; done
[[ "$HAS_SAVE" -eq 1 ]] && echo "  → Save/ (keep most recent)"
echo ""

for dir in "${OVERWRITE_DIRS[@]}"; do
    echo "--- Syncing $dir/ ---"
    rsync -av --progress "$SRC/$dir/" "${DEST_BASE}/$dir/"
    echo ""
done

if [[ "$HAS_SAVE" -eq 1 ]]; then
    echo "--- Syncing Save/ (keep most recent) ---"
    rsync -av --update --progress "$SRC/Save/" "${DEST_BASE}/Save/"
    echo ""
fi

echo "Fixing ownership on arcade..."
ssh "pump@${ARCADE}" 'sudo chown -R pump:pump /mnt/xsanity/Songs /mnt/xsanity/SongMovies /mnt/xsanity/Avatars /mnt/xsanity/NoteSkins /mnt/xsanity/Save 2>/dev/null || true'

echo ""
read -rp "Reboot arcade now to rebuild cache? [y/N] " reboot
[[ "${reboot:-N}" =~ ^[Yy] ]] && ssh "pump@${ARCADE}" 'sudo reboot'
echo "Done."
