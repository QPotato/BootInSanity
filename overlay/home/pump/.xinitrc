#!/bin/sh
# Disable X screensaver / DPMS for arcade kiosk use.
xset s off
xset s noblank
xset -dpms

# 720p preferred resolution (xrandr fallback if VirtualBox/QEMU exposes oddities).
xrandr --output "$(xrandr | awk '/ connected/ {print $1; exit}')" --mode 1280x720 --rate 60 2>/dev/null || true

exec i3
