#!/bin/bash
# Win+X: expand the data partition (sp-data, p3) to fill remaining disk space.
# Safe to run multiple times — growpart is idempotent if partition already fills disk.

lxterminal --title="Expand Data Partition" -e bash -c "
    set -euo pipefail

    # Find the block device for the sp-data partition.
    DATA_DEV=\$(blkid -L sp-data 2>/dev/null || true)
    if [[ -z \"\$DATA_DEV\" ]]; then
        echo 'ERROR: sp-data partition not found.'
        echo 'This command only works on the installed system, not the live ISO.'
        sleep 5; exit 1
    fi

    # Derive disk + partition number.
    # e.g. /dev/sda3 → disk=/dev/sda, partnum=3
    #      /dev/nvme0n1p3 → disk=/dev/nvme0n1, partnum=3
    DISK=\$(lsblk -no PKNAME \"\$DATA_DEV\" | head -1)
    DISK=\"/dev/\$DISK\"
    PARTNUM=\$(cat /sys/class/block/\$(basename \$DATA_DEV)/partition)

    echo \"Data partition: \$DATA_DEV (partition \$PARTNUM of \$DISK)\"
    echo

    BEFORE=\$(df -h \"\$DATA_DEV\" 2>/dev/null | tail -1 || true)
    echo \"Before: \$BEFORE\"
    echo

    echo 'Expanding partition...'
    sudo growpart \"\$DISK\" \"\$PARTNUM\"

    echo 'Resizing filesystem...'
    sudo resize2fs \"\$DATA_DEV\"

    AFTER=\$(df -h \"\$DATA_DEV\" 2>/dev/null | tail -1 || true)
    echo
    echo \"After:  \$AFTER\"
    echo 'Done.'
    sleep 5
"
