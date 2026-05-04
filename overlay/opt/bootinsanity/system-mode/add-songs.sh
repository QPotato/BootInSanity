#!/bin/bash
# Win+S: copy songs from USB stick to /mnt/xsanity/Songs/.
# Opens in a terminal, shows rsync progress, fixes ownership.

DEST=/mnt/xsanity/Songs

lxterminal --title="Add Songs" -e bash -c '
set -euo pipefail

DEST=/mnt/xsanity/Songs

echo "======================================="
echo " BootInSanity — Add Songs from USB"
echo "======================================="
echo ""

# Find USB mount points under /media
USB_MOUNTS=( $(findmnt -rno TARGET /media/pump/ 2>/dev/null; \
               find /media/pump /run/media /mnt -maxdepth 2 -type d -name "Songs" 2>/dev/null \
                 | sed "s|/Songs$||") )

# Also check any vfat/exfat/ntfs mounts
while IFS= read -r mp; do
    [[ "$mp" == /media/* || "$mp" == /run/media/* ]] && USB_MOUNTS+=("$mp")
done < <(findmnt -rno TARGET,FSTYPE 2>/dev/null | awk '\''$2~/vfat|exfat|ntfs|fuseblk/{print $1}'\'')

# Deduplicate
mapfile -t USB_MOUNTS < <(printf "%s\n" "${USB_MOUNTS[@]}" | sort -u)

# Find ones that actually have a Songs dir
SOURCES=()
for mp in "${USB_MOUNTS[@]}"; do
    [[ -d "$mp/Songs" ]] && SOURCES+=("$mp/Songs")
done

if [[ ${#SOURCES[@]} -eq 0 ]]; then
    echo "No USB stick with a Songs/ folder found."
    echo ""
    echo "Insert USB stick and run again, or copy songs manually:"
    echo "  rsync -av /media/pump/<usb>/Songs/ $DEST/"
    echo ""
    read -rp "Press Enter to close..."
    exit 1
fi

if [[ ${#SOURCES[@]} -gt 1 ]]; then
    echo "Multiple sources found:"
    for i in "${!SOURCES[@]}"; do
        echo "  [$i] ${SOURCES[$i]}"
    done
    echo ""
    read -rp "Choose [0]: " choice
    choice="${choice:-0}"
    SRC="${SOURCES[$choice]}"
else
    SRC="${SOURCES[0]}"
fi

echo "Source : $SRC"
echo "Dest   : $DEST"
echo ""
read -rp "Proceed? [Y/n] " confirm
confirm="${confirm:-Y}"
[[ "$confirm" =~ ^[Yy] ]] || { echo "Cancelled."; read -rp "Press Enter..."; exit 0; }

echo ""
rsync -av --progress --ignore-existing "$SRC/" "$DEST/"
chown -R pump:pump "$DEST"

echo ""
echo "Done. Reboot to rebuild XSanity cache."
echo ""
read -rp "Reboot now? [y/N] " reboot
[[ "$reboot" =~ ^[Yy] ]] && systemctl reboot
' &
