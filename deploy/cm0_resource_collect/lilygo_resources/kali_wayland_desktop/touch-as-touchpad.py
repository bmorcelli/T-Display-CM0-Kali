#!/usr/bin/env python3
"""Reads the AMOLED panel's absolute touchscreen and drives a virtual
relative-pointer mouse from it (drag to move, one-finger tap to left
click, two-finger tap to right click), since libinput has no touchpad
emulation mode for touch hardware and this panel's digitizer cannot be
reclassified as a touchpad (tested: it stops responding entirely).
Grabs the touch device exclusively so the compositor only ever sees the
synthetic mouse, never raw absolute touch.
"""
import time
import evdev
from evdev import ecodes as e

TOUCH_DEVICE_NAME = "Goodix Berlin Capacitive TouchScreen"
SENSITIVITY = 0.6       # raw-unit movement -> relative mouse counts
TAP_MAX_DISTANCE = 80   # raw units of distance from touch-down to still count as a tap
TAP_MAX_DURATION = 0.35  # seconds


def find_touch_device():
    for path in evdev.list_devices():
        dev = evdev.InputDevice(path)
        if dev.name == TOUCH_DEVICE_NAME:
            return dev
    raise RuntimeError(f"touch device {TOUCH_DEVICE_NAME!r} not found")


def make_virtual_mouse():
    cap = {
        e.EV_REL: [e.REL_X, e.REL_Y],
        e.EV_KEY: [e.BTN_LEFT, e.BTN_RIGHT],
    }
    return evdev.UInput(cap, name="cm0-touch-as-touchpad")


def click(mouse, button):
    mouse.write(e.EV_KEY, button, 1)
    mouse.syn()
    mouse.write(e.EV_KEY, button, 0)
    mouse.syn()


def main():
    touch = find_touch_device()
    touch.grab()
    mouse = make_virtual_mouse()

    slots = {}       # slot -> {'x':.., 'y':..}
    cur_slot = 0

    primary_slot = None   # slot driving relative pointer motion
    primary_last = None   # (x, y) of primary slot's previous position
    gesture_start_x = gesture_start_y = None
    gesture_start_time = 0.0
    gesture_max_fingers = 0

    def active_slots():
        return [s for s in slots if slots[s].get('id', -1) != -1]

    try:
        for ev in touch.read_loop():
            if ev.type == e.EV_ABS:
                if ev.code == e.ABS_MT_SLOT:
                    cur_slot = ev.value
                elif ev.code == e.ABS_MT_TRACKING_ID:
                    slot = slots.setdefault(cur_slot, {})
                    was_active = len(active_slots())
                    slot['id'] = ev.value
                    now_active = len(active_slots())

                    if was_active == 0 and now_active == 1:
                        gesture_start_time = time.time()
                        gesture_max_fingers = 1
                        gesture_start_x = gesture_start_y = None
                    elif now_active > was_active:
                        gesture_max_fingers = max(gesture_max_fingers, now_active)

                    if ev.value == -1 and cur_slot == primary_slot:
                        primary_slot = None
                        primary_last = None

                    if now_active == 0 and was_active > 0:
                        duration = time.time() - gesture_start_time
                        distance = 0
                        if gesture_start_x is not None:
                            distance = abs(slots.get(cur_slot, {}).get('x', gesture_start_x) - gesture_start_x) + \
                                       abs(slots.get(cur_slot, {}).get('y', gesture_start_y) - gesture_start_y)
                        if duration <= TAP_MAX_DURATION and distance <= TAP_MAX_DISTANCE:
                            if gesture_max_fingers == 1:
                                click(mouse, e.BTN_LEFT)
                            elif gesture_max_fingers == 2:
                                click(mouse, e.BTN_RIGHT)
                        gesture_max_fingers = 0
                elif ev.code in (e.ABS_MT_POSITION_X, e.ABS_X):
                    slots.setdefault(cur_slot, {})['x'] = ev.value
                    if gesture_start_x is None:
                        gesture_start_x = ev.value
                elif ev.code in (e.ABS_MT_POSITION_Y, e.ABS_Y):
                    slots.setdefault(cur_slot, {})['y'] = ev.value
                    if gesture_start_y is None:
                        gesture_start_y = ev.value
            elif ev.type == e.EV_SYN and ev.code == e.SYN_REPORT:
                active = active_slots()

                if len(active) == 1:
                    slot = active[0]
                    pos = slots[slot]
                    if 'x' in pos and 'y' in pos:
                        if primary_slot != slot:
                            primary_slot = slot
                            primary_last = None
                        if primary_last is not None:
                            raw_dx = pos['x'] - primary_last[0]
                            raw_dy = pos['y'] - primary_last[1]
                            # Same linear part as the labwc calibrationMatrix
                            # "0 -1 1 1 0 0" (90 deg cw) used for absolute
                            # touch, so drag direction matches the rotated
                            # panel.
                            dx = -raw_dy
                            dy = raw_dx
                            if dx or dy:
                                mouse.write(e.EV_REL, e.REL_X, int(dx * SENSITIVITY))
                                mouse.write(e.EV_REL, e.REL_Y, int(dy * SENSITIVITY))
                                mouse.syn()
                        primary_last = (pos['x'], pos['y'])
                else:
                    primary_slot = None
                    primary_last = None
    finally:
        touch.ungrab()
        mouse.close()


if __name__ == "__main__":
    main()
