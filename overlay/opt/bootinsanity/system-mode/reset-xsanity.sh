#!/bin/bash
# Win+R: reset XSanity settings and scores back to defaults.
# Deletes Save/ contents except LocalProfiles/ (player profiles are kept).
# launch.sh will re-seed Preferences.ini on next start.

XSANITY_DIR=/mnt/xsanity
SAVE_DIR="${XSANITY_DIR}/Save"

lxterminal --title="Reset XSanity Settings" -e bash -c "
    echo 'This will reset XSanity settings and scores.'
    echo 'LocalProfiles/ (player profiles) will NOT be deleted.'
    echo 'Game data (songs, noteskins) will NOT be affected.'
    echo
    read -p 'Type YES to confirm: ' confirm
    if [[ \"\$confirm\" == 'YES' ]]; then
        find '$SAVE_DIR' -mindepth 1 -maxdepth 1 \
            ! -name 'LocalProfiles' -exec rm -rf {} +
        echo 'Done. Settings reset. Restart XSanity to apply.'
    else
        echo 'Cancelled.'
    fi
    sleep 3
"
