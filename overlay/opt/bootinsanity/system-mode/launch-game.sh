#!/bin/bash
# Win+G: return to game — (re)launch XSanity from system mode.

# Don't launch a second instance if already running.
if pgrep -f "xsanity\|XSanity\.sh" >/dev/null 2>&1; then
    exit 0
fi

DISPLAY=:0 XAUTHORITY=/home/pump/.Xauthority \
    su -c '/opt/bootinsanity/launch.sh' pump &
