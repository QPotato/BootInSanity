#!/bin/bash
# Win+R: reset XSanity settings and high scores back to defaults.
# Deletes Save/ directory; launch.sh will re-seed Preferences.ini on next start.

XSANITY_DIR=/mnt/xsanity
SAVE_DIR="${XSANITY_DIR}/Save"

lxterminal --title="Reset XSanity Settings" -e bash -c "
    echo 'This will delete all XSanity settings and high scores.'
    echo 'Game data (songs, noteskins) will NOT be affected.'
    echo
    read -p 'Type YES to confirm: ' confirm
    if [[ \"\$confirm\" == 'YES' ]]; then
        rm -rf '$SAVE_DIR'
        echo 'Done. Settings reset. Restart XSanity to apply.'
    else
        echo 'Cancelled.'
    fi
    sleep 3
"
