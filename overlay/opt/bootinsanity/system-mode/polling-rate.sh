#!/bin/bash
# Win+E: check USB input device polling rate via evtest.
# Shows available input devices and lets the user pick one to monitor.
exec lxterminal --title="Polling Rate Check" -e bash -c "
    echo 'Available input devices:'
    echo
    sudo evtest --query 2>/dev/null || true
    echo
    echo 'Enter device path to test (e.g. /dev/input/event0),'
    echo 'or press Enter to list and pick interactively:'
    read -p '> ' dev
    if [[ -z \"\$dev\" ]]; then
        sudo evtest
    else
        sudo evtest \"\$dev\"
    fi
"
