#!/bin/bash
# Fullscreen "XSanity not installed" notice when /mnt/xsanity/XSanity.sh is missing.

exec lxterminal --geometry=120x40 -e bash -c '
clear
cat <<MSG

    ============================================================
                       BootInSanity
    ============================================================

      XSanity not found at /mnt/xsanity/XSanity.sh

      To install:
        1. Copy the XSanity 0.96.0 folder contents to:
             /mnt/xsanity/

        2. Reboot.

      Network access:
        sshd is listening on port 22
        user: pump
        pass: pump

        scp -r XSanity/ pump@<this-host>:/mnt/xsanity/

    ============================================================
MSG

while :; do sleep 60; done
'
