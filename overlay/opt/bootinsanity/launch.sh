#!/bin/bash
# BootInSanity XSanity launcher.
# Started by i3 autostart. Crash-loop relaunches XSanity if it exits.
# If XSanity is missing, shows a fullscreen "missing" notice instead.

set -u

LOG=/tmp/bootinsanity-launch.log
mkdir -p "$(dirname "$LOG")"
exec >>"$LOG" 2>&1

echo "=== BootInSanity launch starting at $(date) ==="
echo "user: $(id)"
echo "DISPLAY: ${DISPLAY:-unset}"

XSANITY_DIR=/mnt/xsanity
XSANITY_SH="${XSANITY_DIR}/XSanity.sh"

if [[ ! -x "$XSANITY_SH" ]]; then
    echo "XSanity not present — showing missing-xsanity screen"
    exec /opt/bootinsanity/missing-xsanity.sh
fi

# Unmute ALSA output — ALC662 (MK9) boots with outputs muted.
amixer set Master unmute  2>/dev/null || true
amixer set Master 100%    2>/dev/null || true
amixer set PCM    unmute  2>/dev/null || true
amixer set Speaker unmute 2>/dev/null || true
amixer set Headphone unmute 2>/dev/null || true

# Pre-seed Preferences.ini with ALSA backend if absent.
# SoundDevice=dmix matches pumptools hook.conf and works on ALC662 / Intel HDA.
PREFS="${XSANITY_DIR}/Save/Preferences.ini"
if [[ ! -f "$PREFS" ]]; then
    mkdir -p "${XSANITY_DIR}/Save" 2>/dev/null || true
    cat > "$PREFS" 2>/dev/null <<'EOF' || true
[Options]
SoundDrivers=ALSA-sw
SoundDevice=dmix
DisplayWidth=1280
DisplayHeight=720
DisplayColorDepth=32
RefreshRate=60
Windowed=0
FullscreenIsBorderlessWindow=0
VsyncEnabled=1
EOF
fi

CRASH_COUNT=0
while :; do
    echo "=== launching $XSANITY_SH at $(date) (attempt $((CRASH_COUNT+1))) ==="
    "$XSANITY_SH" 2>&1
    rc=$?
    CRASH_COUNT=$((CRASH_COUNT+1))
    echo "=== XSanity exited rc=$rc at $(date) ==="

    # After 3 rapid crashes enter system mode so the user can inspect logs.
    if [[ $CRASH_COUNT -ge 3 ]]; then
        echo "=== 3 crashes — entering system mode ==="
        exec /opt/bootinsanity/system-mode/exit-to-desktop.sh
    fi
    sleep 1
done
