#!/bin/bash
# Win+S: copy Songs/ and SongMovies/ from USB stick to /mnt/xsanity/.
# Overwrites existing files (step charts get updated).

lxterminal --title="Add Songs" -e bash -c '
set -euo pipefail

DEST=/mnt/xsanity

echo "======================================="
echo " BootInSanity — Add Songs from USB"
echo "======================================="
echo ""

# Find removable mounts with vfat/exfat/ntfs
SOURCES=()
while IFS= read -r mp; do
    [[ -d "$mp/Songs" || -d "$mp/SongMovies" ]] && SOURCES+=("$mp")
done < <(findmnt -rno TARGET,FSTYPE 2>/dev/null \
         | awk '"'"'$2~/vfat|exfat|ntfs|fuseblk/{print $1}'"'"')

# Also check /media/pump subdirs
for mp in /media/pump/*/; do
    [[ -d "$mp/Songs" || -d "$mp/SongMovies" || -d "$mp/Avatars" || -d "$mp/NoteSkins" ]] && SOURCES+=("${mp%/}")
done

# Deduplicate
mapfile -t SOURCES < <(printf "%s\n" "${SOURCES[@]}" | sort -u)

if [[ ${#SOURCES[@]} -eq 0 ]]; then
    echo "No USB stick with Songs/ or SongMovies/ found."
    echo "Insert USB and run again."
    echo ""
    read -rp "Press Enter to close..."
    exit 1
fi

if [[ ${#SOURCES[@]} -gt 1 ]]; then
    echo "Multiple USB sticks found:"
    for i in "${!SOURCES[@]}"; do echo "  [$i] ${SOURCES[$i]}"; done
    echo ""
    read -rp "Choose [0]: " choice
    SRC="${SOURCES[${choice:-0}]}"
else
    SRC="${SOURCES[0]}"
fi

echo "Source : $SRC"
echo "Dest   : $DEST"
echo ""
for dir in Songs SongMovies Avatars NoteSkins; do
    [[ -d "$SRC/$dir" ]] && echo "  $dir/ → will copy + overwrite"
done
echo ""
read -rp "Proceed? [Y/n] " confirm
[[ "${confirm:-Y}" =~ ^[Yy] ]] || { echo "Cancelled."; read -rp "Press Enter..."; exit 0; }
echo ""

for dir in Songs SongMovies Avatars NoteSkins; do
    [[ -d "$SRC/$dir" ]] || continue
    echo "--- Syncing $dir/ ---"
    rsync -av --progress "$SRC/$dir/" "$DEST/$dir/"
    echo ""
done

chown -R pump:pump "$DEST/Songs" "$DEST/SongMovies" "$DEST/Avatars" "$DEST/NoteSkins" 2>/dev/null || true

echo "Done. Reboot to rebuild XSanity cache."
echo ""
read -rp "Reboot now? [y/N] " reboot
[[ "${reboot:-N}" =~ ^[Yy] ]] && systemctl reboot
' &
