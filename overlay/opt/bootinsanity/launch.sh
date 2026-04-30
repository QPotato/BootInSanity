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

# Pre-seed Preferences.ini with ALSA backend if absent.
PREFS="${XSANITY_DIR}/Save/Preferences.ini"
if [[ ! -f "$PREFS" ]]; then
    mkdir -p "${XSANITY_DIR}/Save" 2>/dev/null || true
    cat > "$PREFS" 2>/dev/null <<'EOF' || true
[Options]
SoundDrivers=ALSA-sw
SoundDevice=default
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

    # Debug aid: after 3 rapid failures, drop to a terminal so the user
    # can inspect logs. Phase 4 replaces this with proper system mode.
    if [[ $CRASH_COUNT -ge 3 ]]; then
        echo "=== 3 crashes — opening lxterminal for debug ==="
        lxterminal -e bash -c "
            echo 'BootInSanity — XSanity has crashed 3 times.'
            echo 'Log: /tmp/bootinsanity-launch.log'
            echo
            echo 'Press Enter to retry, or Ctrl+D to exit terminal.'
            tail -n 50 /tmp/bootinsanity-launch.log
            read line || true
            exec bash
        "
        CRASH_COUNT=0
    fi
    sleep 1
done
