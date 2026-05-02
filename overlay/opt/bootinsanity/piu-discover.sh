#!/bin/bash
# Scan /mnt/piu/ for PIU version images and update launcher registry.
# Run at: first boot (via firstboot.sh), and after user adds new versions.
# Safe to re-run at any time (idempotent).

set -euo pipefail

PIU_BASE="/mnt/piu"
REGISTRY="/var/lib/bootinsanity/piu-versions"

mkdir -p "$(dirname "$REGISTRY")"

# Collect: all .img.gz files OR already-extracted dirs matching pattern.
mapfile -t FOUND < <(
    find "$PIU_BASE" -maxdepth 1 \( \
        -name '[0-9][0-9]_*.img.gz' -o \
        -type d -name '[0-9][0-9]_*' \
    \) 2>/dev/null \
    | sed 's|\.img\.gz$||' \
    | sort -u
)

> "$REGISTRY"
for path in "${FOUND[@]}"; do
    name="$(basename "$path")"
    echo "$name|$path" >> "$REGISTRY"
    echo "    Found: $name"
done

COUNT="${#FOUND[@]}"
echo "piu-discover: $COUNT version(s) registered at $REGISTRY"
