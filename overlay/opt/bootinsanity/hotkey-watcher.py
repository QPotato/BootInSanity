#!/usr/bin/env python3
# Evdev-level global hotkey watcher for BootInSanity.
# Runs as root, reads /dev/input/* directly — not blocked by XGrabKeyboard.
#
# Hotkeys:
#   Win+F4   → exit-to-desktop (system mode)
#   Win+r    → reset-xsanity
#   Win+v    → volume-mixer
#   Win+m    → configure-memcards
#   Win+b    → reboot
#   Win+p    → poweroff

import evdev
import subprocess
import threading
import time
import os

ACTIONS = {
    evdev.ecodes.KEY_F4:      '/opt/bootinsanity/system-mode/exit-to-desktop.sh',
    evdev.ecodes.KEY_R:       '/opt/bootinsanity/system-mode/reset-xsanity.sh',
    evdev.ecodes.KEY_V:       '/opt/bootinsanity/system-mode/volume-mixer.sh',
    evdev.ecodes.KEY_M:       '/opt/bootinsanity/system-mode/configure-memcards.sh',
    evdev.ecodes.KEY_B:       'systemctl reboot',
    evdev.ecodes.KEY_P:       'systemctl poweroff',
}

META_KEYS = {evdev.ecodes.KEY_LEFTMETA, evdev.ecodes.KEY_RIGHTMETA}

held = set()
last_action = 0
DEBOUNCE = 1.0  # seconds between repeated triggers


def handle_device(dev):
    try:
        dev.grab()
    except Exception:
        pass
    try:
        for event in dev.read_loop():
            if event.type != evdev.ecodes.EV_KEY:
                continue
            key = evdev.categorize(event)
            code = key.scancode
            # Track modifier state
            if code in META_KEYS:
                if key.keystate in (key.key_down, key.key_hold):
                    held.add(code)
                else:
                    held.discard(code)
                continue
            # Key down with Win held
            if key.keystate == key.key_down and held & META_KEYS:
                action = ACTIONS.get(code)
                if action:
                    global last_action
                    now = time.monotonic()
                    if now - last_action < DEBOUNCE:
                        continue
                    last_action = now
                    subprocess.Popen(
                        action, shell=True,
                        env={**os.environ, 'DISPLAY': ':0', 'HOME': '/home/pump'}
                    )
    except (OSError, IOError):
        pass


def watch():
    threads = {}
    while True:
        devs = {p: evdev.InputDevice(p)
                for p in evdev.list_devices()
                if 'keyboard' in (evdev.InputDevice(p).name or '').lower()
                or evdev.ecodes.EV_KEY in evdev.InputDevice(p).capabilities()}
        for path, dev in devs.items():
            if path not in threads or not threads[path].is_alive():
                t = threading.Thread(target=handle_device, args=(dev,), daemon=True)
                t.start()
                threads[path] = t
        time.sleep(3)


if __name__ == '__main__':
    watch()
