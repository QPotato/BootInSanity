#!/bin/bash
# Push Songs/ and/or SongMovies/ from a local directory to the arcade.
# Overwrites existing files (step charts get updated).
#
# Usage:
#   ./scripts/push-songs.sh <source-dir> [arcade-ip]
#
# Examples:
#   ./scripts/push-songs.sh ~/Songs
#   ./scripts/push-songs.sh ~/Songs 192.168.100.2
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
DIRS=()
for dir in Songs SongMovies Avatars NoteSkins; do
    if [[ -d "$SRC/$dir" ]]; then
        DIRS+=("$dir")
    elif [[ "$(basename "$SRC")" == "$dir" ]]; then
        # User passed the Songs/ dir directly rather than its parent
        DIRS+=("$dir")
        SRC="$(dirname "$SRC")"
    fi
done

if [[ ${#DIRS[@]} -eq 0 ]]; then
    echo "ERROR: $SRC contains none of: Songs/ SongMovies/ Avatars/ NoteSkins/" >&2
    exit 1
fi

echo "Arcade : $ARCADE"
echo "Source : $SRC"
for dir in "${DIRS[@]}"; do echo "  → $dir/"; done
echo ""

for dir in "${DIRS[@]}"; do
    echo "--- Syncing $dir/ ---"
    rsync -av --progress "$SRC/$dir/" "${DEST_BASE}/$dir/"
    echo ""
done

echo "Fixing ownership on arcade..."
ssh "pump@${ARCADE}" 'sudo chown -R pump:pump /mnt/xsanity/Songs /mnt/xsanity/SongMovies /mnt/xsanity/Avatars /mnt/xsanity/NoteSkins 2>/dev/null || true'

echo ""
read -rp "Reboot arcade now to rebuild cache? [y/N] " reboot
[[ "${reboot:-N}" =~ ^[Yy] ]] && ssh "pump@${ARCADE}" 'sudo reboot'
echo "Done."
