#!/bin/bash
# Build out-of-tree kernel modules required by BootInSanity:
#   - usbhid (patched 1ms polling)
#   - piuio (djpohly/piuio: Andamiro PIUIO board → Linux joystick)
#
# Runs at build time inside the chroot.

set -euo pipefail

PATCH=/tmp/usbhid-1ms.patch

# Refresh apt index (mmdebstrap wipes /var/lib/apt/lists/ after bootstrap).
apt-get update >/dev/null

# Build deps. Upgrade kernel + headers + source together so KVER matches
# linux-headers-amd64 metapackage (the user's DVD kernel may have rolled
# forward via security archive).
apt-get install -y --no-install-recommends \
    linux-image-amd64 linux-headers-amd64 \
    build-essential bc kmod cpio flex bison \
    libssl-dev libelf-dev rsync \
    python3 \
    git ca-certificates

# linux-source-5.10 ships a tarball at /usr/src/linux-source-5.10.tar.xz that
# the previous build's cleanup wipes. Force reinstall so the tarball is
# present even on cached chroot rebuilds.
apt-get install -y --reinstall --no-install-recommends linux-source-5.10

# Re-detect KVER after the upgrade so we build for the kernel that ships.
KVER="$(ls -1 /boot/ | grep '^vmlinuz-' | sort -V | tail -1 | sed 's|^vmlinuz-||')"
[[ -n "$KVER" ]] || { echo "ERROR: no kernel installed in chroot" >&2; exit 1; }
echo "==> kernel target: $KVER"

HEADERS=/usr/src/linux-headers-${KVER}
[[ -d "$HEADERS" ]] || { echo "ERROR: $HEADERS missing" >&2; exit 1; }

UPDATES=/lib/modules/${KVER}/updates
EXTRA=/lib/modules/${KVER}/extra
mkdir -p "$UPDATES" "$EXTRA"

# ---------------------------------------------------------------------------
# 1. usbhid 1 ms patch
# ---------------------------------------------------------------------------
echo "==> [1/2] usbhid 1ms patch build"

SRC=/usr/src/linux-source-5.10
TARBALL=/usr/src/linux-source-5.10.tar.xz
[[ -f "$TARBALL" ]] || { echo "ERROR: $TARBALL missing" >&2; exit 1; }

if [[ ! -d "$SRC" ]]; then
    cd /usr/src
    tar -xf "$TARBALL"
fi

cd "$SRC"

TARGET=drivers/hid/usbhid/hid-core.c
if ! grep -q '^static unsigned int hid_elsepoll_interval;' "$TARGET"; then
    echo "    applying usbhid 1ms patch"
    patch -p0 --forward "$TARGET" <"$PATCH"
fi

cp "$HEADERS/.config" .config
cp "$HEADERS/Module.symvers" Module.symvers 2>/dev/null || true
make ARCH=x86_64 olddefconfig >/dev/null
make ARCH=x86_64 prepare >/dev/null
make ARCH=x86_64 modules_prepare >/dev/null

make ARCH=x86_64 -C "$HEADERS" M="$SRC/drivers/hid/usbhid" modules

cp drivers/hid/usbhid/usbhid.ko "$UPDATES/usbhid.ko"
strip --strip-debug "$UPDATES/usbhid.ko" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 2. djpohly/piuio module
# ---------------------------------------------------------------------------
echo "==> [2/2] djpohly/piuio module build"

PIUIO_SRC=/usr/src/piuio
rm -rf "$PIUIO_SRC"
git clone --depth=1 https://github.com/djpohly/piuio "$PIUIO_SRC"

cd "$PIUIO_SRC/mod"
make KDIR="$HEADERS"

# Install: prefer extra/ since piuio is a wholly new module (not a replacement).
cp piuio.ko "$EXTRA/piuio.ko"
strip --strip-debug "$EXTRA/piuio.ko" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Refresh module dependency tables
# ---------------------------------------------------------------------------
depmod -a "$KVER"

# Rebuild initramfs so our patched usbhid is what loads at early boot (stock
# kernel/.../usbhid.ko is otherwise pulled in first and blocks the updates/
# replacement until userspace explicitly rmmod+modprobe).
update-initramfs -u -k "$KVER"

echo "==> installed modules:"
modinfo "$UPDATES/usbhid.ko" | grep -E '^(filename|vermagic|^parm: (kbpoll|jspoll|elsepoll|mousepoll))' | head -8
echo
modinfo "$EXTRA/piuio.ko" | grep -E '^(filename|vermagic|description|alias)' | head -8

# ---------------------------------------------------------------------------
# Cleanup: remove extracted source trees + apt cache. Keep installed build
# deps (purging them has been observed to wipe /boot via dpkg postrm).
# ---------------------------------------------------------------------------
echo "==> cleanup"
cd /
rm -rf "$SRC" "$TARBALL" "$PIUIO_SRC"
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "==> /boot:"
ls /boot/
