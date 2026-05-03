#!/bin/bash
# Win+F4 / crash-loop fallback: kill XSanity and drop to desktop.
# Called from i3 keybind or from launch.sh after 3 consecutive crashes.

set -euo pipefail

LOG=/tmp/bootinsanity-launch.log

echo "=== system mode entered at $(date) ===" >> "$LOG"

# Kill XSanity and the crash-loop (don't kill ourselves).
pkill -f "XSanity\.sh" 2>/dev/null || true
pkill -f "xsanity\|stepmania\|openitg" 2>/dev/null || true
# Kill any remaining launch.sh that is not us.
pkill -f "bootinsanity/launch\.sh" 2>/dev/null || true

sleep 0.3

# Open a terminal pre-loaded with the crash log.
lxterminal --title="BootInSanity — System Mode" -e bash -c "
    echo '======================================='
    echo ' BootInSanity — System Mode'
    echo '======================================='
    echo ''
    echo 'XSanity has been stopped.'
    echo 'Crash log: $LOG'
    echo ''
    echo 'Keybinds:'
    echo '  Win+Enter   New terminal'
    echo '  Win+M       Memory cards (file manager)'
    echo '  Win+R       Reset XSanity settings'
    echo '  Win+V       Volume mixer'
    echo '  Win+E       Polling rate check'
    echo '  Win+X       Expand data partition'
    echo '  Win+B       Reboot'
    echo '  Win+P       Power off'
    echo ''
    echo 'Last 30 lines of launch log:'
    echo '---------------------------------------'
    tail -n 30 $LOG 2>/dev/null || echo '(no log)'
    echo '---------------------------------------'
    exec bash
" &
