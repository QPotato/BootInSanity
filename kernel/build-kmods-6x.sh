#!/bin/bash
# Build out-of-tree kernel modules for BootInSanity on kernel 6.x (trixie).
#
# Produces:
#   - usbhid.ko (patched for 1ms elsepoll on non-mouse/kb/joystick HID devices)
#
# Note: piuio kmod is NOT built here — replaced by PIUIO2Key-Linux (userspace).
#
# Runs at ISO build time inside the chroot (called from build.sh step [4c/9]).

set -euo pipefail

PATCH_PY=/tmp/patch-usbhid.py

apt-get update -qq

# Build deps — install metapackages first so kernel is current before we probe KVER.
apt-get install -y --no-install-recommends \
    linux-image-amd64 linux-headers-amd64 \
    build-essential bc kmod cpio flex bison \
    libssl-dev libelf-dev rsync \
    python3

# Determine the actual kernel version installed (highest in /boot).
KVER="$(ls -1 /boot/ | grep '^vmlinuz-' | sort -V | tail -1 | sed 's|^vmlinuz-||')"
[[ -n "$KVER" ]] || { echo "ERROR: no kernel in /boot" >&2; exit 1; }
KMAJ="${KVER%%.*}"
KMIN="${KVER#*.}"; KMIN="${KMIN%%.*}"
echo "==> kernel target: $KVER (${KMAJ}.${KMIN})"

HEADERS="/usr/src/linux-headers-${KVER}"
[[ -d "$HEADERS" ]] || { echo "ERROR: $HEADERS missing" >&2; exit 1; }

# Install the matching linux-source tarball.
# Cached chroot may have a stale kernel version whose source is no longer in
# the repos.  If the exact package is unavailable, upgrade the kernel
# metapackage (already done above) and re-probe KVER — then try again.
SOURCE_PKG="linux-source-${KMAJ}.${KMIN}"
TARBALL="/usr/src/${SOURCE_PKG}.tar.xz"
if [[ ! -f "$TARBALL" ]]; then
    apt-get remove --purge -y "$SOURCE_PKG" 2>/dev/null || true
    if ! apt-cache show "$SOURCE_PKG" &>/dev/null; then
        echo "    WARN: $SOURCE_PKG not in repos — re-probing after kernel upgrade"
        # Headers metapackage already upgraded kernel; re-detect KVER.
        KVER="$(ls -1 /boot/ | grep '^vmlinuz-' | sort -V | tail -1 | sed 's|^vmlinuz-||')"
        KMAJ="${KVER%%.*}"
        KMIN="${KVER#*.}"; KMIN="${KMIN%%.*}"
        SOURCE_PKG="linux-source-${KMAJ}.${KMIN}"
        TARBALL="/usr/src/${SOURCE_PKG}.tar.xz"
        HEADERS="/usr/src/linux-headers-${KVER}"
        echo "    re-probed kernel: $KVER — trying $SOURCE_PKG"
        apt-get install -y --no-install-recommends \
            "linux-headers-${KVER}" "$SOURCE_PKG" 2>/dev/null \
            || apt-get install -y --no-install-recommends linux-headers-amd64 "$SOURCE_PKG"
    else
        apt-get install -y --no-install-recommends "$SOURCE_PKG"
    fi
fi
[[ -f "$TARBALL" ]] || { echo "ERROR: $TARBALL missing after install" >&2; exit 1; }

SRC="/usr/src/${SOURCE_PKG}"
if [[ ! -d "$SRC" ]]; then
    echo "    Extracting $TARBALL ..."
    cd /usr/src
    tar -xf "$TARBALL"
fi

# Apply elsepoll patch.
TARGET="$SRC/drivers/hid/usbhid/hid-core.c"
[[ -f "$TARGET" ]] || { echo "ERROR: $TARGET not found in source tree" >&2; exit 1; }
python3 "$PATCH_PY" "$TARGET"

# Configure and prepare the source tree so we can build a single module.
cd "$SRC"
cp "$HEADERS/.config" .config
cp "$HEADERS/Module.symvers" Module.symvers 2>/dev/null || true
make ARCH=x86_64 olddefconfig >/dev/null
make ARCH=x86_64 prepare >/dev/null
make ARCH=x86_64 modules_prepare >/dev/null

# Build only the usbhid subdirectory.
make ARCH=x86_64 -C "$HEADERS" M="$SRC/drivers/hid/usbhid" modules

UPDATES="/lib/modules/${KVER}/updates"
mkdir -p "$UPDATES"
cp "$SRC/drivers/hid/usbhid/usbhid.ko" "$UPDATES/usbhid.ko"
strip --strip-debug "$UPDATES/usbhid.ko" 2>/dev/null || true

depmod -a "$KVER"

# Rebuild initramfs so the patched usbhid loads from updates/ at early boot.
update-initramfs -u -k "$KVER"

echo "==> installed modules:"
modinfo "$UPDATES/usbhid.ko" | grep -E '^(filename|vermagic|parm)' | head -10

# Cleanup.
cd /
rm -rf "$SRC" "$TARBALL"
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "==> /boot:"
ls /boot/
