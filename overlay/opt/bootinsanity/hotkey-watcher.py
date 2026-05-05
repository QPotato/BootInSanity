#!/usr/bin/env python3
# Evdev-level global hotkey watcher for BootInSanity.
# Runs as root, reads /dev/input/* directly — not blocked by XGrabKeyboard.
# Does NOT grab devices: XSanity still receives all keyboard events via X11.
#
# Hotkeys:
#   Win+F4   → exit-to-desktop (system mode)
#   Win+g    → launch-game
#   Win+s    → add-songs
#   Win+r    → reset-xsanity
#   Win+v    → volume-mixer
#   Win+x    → expand-p3
#   Win+e    → polling-rate
#   Win+b    → reboot
#   Win+p    → poweroff

import evdev
import subprocess
import threading
import time
import os

ACTIONS = {
    evdev.ecodes.KEY_F4:      '/opt/bootinsanity/system-mode/exit-to-desktop.sh',
    evdev.ecodes.KEY_G:       '/opt/bootinsanity/system-mode/launch-game.sh',
    evdev.ecodes.KEY_S:       '/opt/bootinsanity/system-mode/add-songs.sh',
    evdev.ecodes.KEY_R:       '/opt/bootinsanity/system-mode/reset-xsanity.sh',
    evdev.ecodes.KEY_V:       '/opt/bootinsanity/system-mode/volume-mixer.sh',
    evdev.ecodes.KEY_X:       '/opt/bootinsanity/system-mode/expand-p3.sh',
    evdev.ecodes.KEY_E:       '/opt/bootinsanity/system-mode/polling-rate.sh',
    evdev.ecodes.KEY_B:       'systemctl reboot',
    evdev.ecodes.KEY_P:       'systemctl poweroff',
}

META_KEYS = {evdev.ecodes.KEY_LEFTMETA, evdev.ecodes.KEY_RIGHTMETA}

held = set()
last_action = 0
DEBOUNCE = 1.0  # seconds between repeated triggers


def is_keyboard(dev):
    caps = dev.capabilities()
    keys = caps.get(evdev.ecodes.EV_KEY, [])
    # Must have letter keys — excludes mice, PIUIO, and other EV_KEY devices
    return evdev.ecodes.KEY_A in keys and evdev.ecodes.KEY_Z in keys


def handle_device(dev):
    try:
        for event in dev.read_loop():
            if event.type != evdev.ecodes.EV_KEY:
                continue
            key = evdev.categorize(event)
            code = key.scancode
            if code in META_KEYS:
                if key.keystate in (key.key_down, key.key_hold):
                    held.add(code)
                else:
                    held.discard(code)
                continue
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
        for path in evdev.list_devices():
            if path in threads and threads[path].is_alive():
                continue
            try:
                dev = evdev.InputDevice(path)
                if not is_keyboard(dev):
                    dev.close()
                    continue
                t = threading.Thread(target=handle_device, args=(dev,), daemon=True)
                t.start()
                threads[path] = t
            except (OSError, IOError):
                pass
        time.sleep(3)


if __name__ == '__main__':
    watch()
