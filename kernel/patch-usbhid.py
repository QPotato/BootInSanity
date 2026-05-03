#!/usr/bin/env python3
"""
Apply the usbhid elsepoll patch to drivers/hid/usbhid/hid-core.c.

Adds an 'elsepoll' module parameter that forces a custom poll interval on
USB HID devices that are not mice, joysticks, or keyboards — e.g. PIUIO
boards (if accessed via usbhid rather than raw libusb).

Works across kernel 5.x and 6.x by matching stable string anchors rather
than line numbers.

Usage: python3 patch-usbhid.py <path-to-hid-core.c>
"""
import re
import sys

if len(sys.argv) != 2:
    print(f"Usage: {sys.argv[0]} <hid-core.c>", file=sys.stderr)
    sys.exit(1)

path = sys.argv[1]
with open(path) as f:
    src = f.read()

if "hid_elsepoll_interval" in src:
    print("hid-core.c: already patched — skipping")
    sys.exit(0)

# ---------------------------------------------------------------------------
# 1. Insert elsepoll module param block after the kbpoll PARM_DESC line.
# ---------------------------------------------------------------------------
KBPOLL_DESC = 'MODULE_PARM_DESC(kbpoll, "Polling interval of keyboards");'
if KBPOLL_DESC not in src:
    print("ERROR: MODULE_PARM_DESC(kbpoll, ...) not found in hid-core.c", file=sys.stderr)
    sys.exit(1)

ELSEPOLL_BLOCK = (
    "\n"
    "static unsigned int hid_elsepoll_interval;\n"
    'module_param_named(elsepoll, hid_elsepoll_interval, uint, 0644);\n'
    'MODULE_PARM_DESC(elsepoll, "Polling interval of non-mouse non-joysticks");\n'
)
src = src.replace(KBPOLL_DESC, KBPOLL_DESC + ELSEPOLL_BLOCK, 1)

# ---------------------------------------------------------------------------
# 2. Insert a default: case into the switch(hid->collection->usage) that
#    handles poll intervals.  The switch has cases for HID_GD_MOUSE,
#    HID_GD_JOYSTICK, and HID_GD_KEYBOARD.  We insert default: after the
#    keyboard case's break and before the closing } of the switch.
#
#    Pattern (stable across 5.x / 6.x):
#      case HID_GD_KEYBOARD:
#          ... (optional printk in 5.10 patch)
#          if (hid_kbpoll_interval > 0)
#              interval = hid_kbpoll_interval;
#          break;
#      }   <-- closing brace of the switch
# ---------------------------------------------------------------------------
pat = re.compile(
    r"(case HID_GD_KEYBOARD:.*?break;)"   # keyboard case including break
    r"(\s*\n(\t+)\})",                     # newline + indent + closing }
    re.DOTALL,
)

def inject_default(m):
    indent = m.group(3)  # indent level of the closing }
    inner = indent + "\t"
    default_case = (
        f"\n{indent}default:\n"
        f"{inner}if (hid_elsepoll_interval > 0)\n"
        f"{inner}\tinterval = hid_elsepoll_interval;\n"
        f"{inner}break;"
    )
    return m.group(1) + default_case + m.group(2)

src, count = pat.subn(inject_default, src, count=1)
if count != 1:
    print("ERROR: could not locate HID_GD_KEYBOARD case in switch — patch failed",
          file=sys.stderr)
    sys.exit(1)

with open(path, "w") as f:
    f.write(src)

print("hid-core.c: patched successfully (elsepoll param added)")
