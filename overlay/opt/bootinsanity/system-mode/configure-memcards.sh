#!/bin/bash
# Win+M: open file manager at USB media mount point.
exec pcmanfm /media/pump 2>/dev/null || exec pcmanfm /media || exec pcmanfm ~
