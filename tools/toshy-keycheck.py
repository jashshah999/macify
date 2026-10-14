"""macify: offline check of what Toshy will turn each physical key combo into, per app.
Run with Toshy's own interpreter:  ~/.config/toshy/.venv/bin/python tools/toshy-keycheck.py
It loads your live config into run the keymapper engine in-process with a fake input device, a fake window context and a fake
output device, feeds physical key sequences and prints what would be emitted. Nothing here touches
/dev/input, /dev/uinput or your running session."""
import os
import sys
import time

os.chdir(os.path.expanduser("~/.config/toshy"))
sys.path.insert(0, os.getcwd())

from evdev import InputEvent, ecodes  # noqa: E402

import xwaykeyz.cli as cli  # noqa: E402
import xwaykeyz.output as output  # noqa: E402
import xwaykeyz.transform as T  # noqa: E402
from xwaykeyz.models.key import Key  # noqa: E402


class FakeUInput:
    def __init__(self):
        self.events = []

    def write(self, etype, code, value):
        if etype == ecodes.EV_KEY:
            self.events.append((int(code), int(value)))

    def write_event(self, event):
        if event.type == ecodes.EV_KEY:
            self.events.append((int(event.code), int(event.value)))

    def syn(self):
        pass


class FakeDevice:
    name = "AT Translated Set 2 keyboard"
    path = "/dev/input/fake0"
    fn = path

    def leds(self):
        return []


class FakeWindowContext:
    def __init__(self):
        self.wm_class, self.wm_name = "", ""

    def get_window_context(self):
        return {"wm_class": self.wm_class, "wm_name": self.wm_name, "wndw_ctxt_error": False}


sink = FakeUInput()
output.setup_uinput(sink)
cli.eval_config(os.path.expanduser("~/.config/toshy/toshy_config.py"))
T.boot_config()
ctx = FakeWindowContext()
T.window_context = ctx
try:
    cli.cnfg.screen_has_focus = True
except AttributeError:
    pass

_clock = [time.time()]


def feed(code, value):
    _clock[0] += 0.05
    sec = int(_clock[0])
    usec = int((_clock[0] - sec) * 1e6)
    T.on_event(InputEvent(sec, usec, ecodes.EV_KEY, code, value), FakeDevice())


def combo(*names):
    """press the named physical keys in order, release in reverse; return the emitted key events"""
    codes = [getattr(ecodes, "KEY_" + n) for n in names]
    sink.events.clear()
    for c in codes:
        feed(c, 1)
    for c in reversed(codes):
        feed(c, 0)
    time.sleep(0.05)
    return list(sink.events)


def fmt(events):
    out = []
    for code, value in events:
        try:
            name = Key(code).name
        except ValueError:
            name = str(code)
        out.append(("+" if value == 1 else "-" if value == 0 else "~") + name)
    return " ".join(out) if out else "(nothing)"


def pressed_combo(events):
    """the keys that are down at the moment the last non-modifier key goes down (what the app sees)"""
    down = []
    last = None
    for code, value in events:
        name = Key(code).name
        if value == 1:
            if name not in down:
                down.append(name)
            last = list(down)
    return "+".join(last) if last else "(nothing)"


cases = [
    ("firefox", "Mozilla Firefox", [
        ("Cmd+C  (physical Alt+C)", ["LEFTALT", "C"]),
        ("Cmd+V  (physical Alt+V)", ["LEFTALT", "V"]),
        ("Cmd+Space", ["LEFTALT", "SPACE"]),
        ("Cmd+Tab", ["LEFTALT", "TAB"]),
        ("Cmd+Q", ["LEFTALT", "Q"]),
        ("Cmd+W", ["LEFTALT", "W"]),
        ("Cmd+T", ["LEFTALT", "T"]),
        ("Cmd+Shift+3 (screenshot)", ["LEFTALT", "LEFTSHIFT", "3"]),
        ("Ctrl+Up  (physical Ctrl+Up)", ["LEFTCTRL", "UP"]),
        ("Ctrl+Left", ["LEFTCTRL", "LEFT"]),
        ("Ctrl+Right", ["LEFTCTRL", "RIGHT"]),
        ("Option+Left (physical Win+Left)", ["LEFTMETA", "LEFT"]),
        ("plain letter a", ["A"]),
    ]),
    ("gnome-terminal-server", "Terminal", [
        ("Cmd+C  (physical Alt+C)", ["LEFTALT", "C"]),
        ("Cmd+V", ["LEFTALT", "V"]),
        ("Ctrl+C (physical, interrupt)", ["LEFTCTRL", "C"]),
        ("Cmd+T", ["LEFTALT", "T"]),
    ]),
    ("org.gnome.Nautilus", "Home", [
        ("Cmd+Backspace (trash)", ["LEFTALT", "BACKSPACE"]),
        ("Cmd+Up (parent folder)", ["LEFTALT", "UP"]),
        ("Cmd+Shift+N (new folder)", ["LEFTALT", "LEFTSHIFT", "N"]),
        ("Cmd+I (get info)", ["LEFTALT", "I"]),
    ]),
    ("jetbrains-pycharm", "project - PyCharm", [
        ("Ctrl+Right (editor tab, not Space)", ["LEFTCTRL", "RIGHT"]),
        ("Cmd+C", ["LEFTALT", "C"]),
    ]),
]

for wm_class, wm_name, seqs in cases:
    ctx.wm_class, ctx.wm_name = wm_class, wm_name
    print(f"\n=== app: {wm_class} ===")
    for label, keys in seqs:
        ev = combo(*keys)
        print(f"  {label:36s} -> {pressed_combo(ev):28s} | {fmt(ev)}")

sys.stdout.flush()
os._exit(0)
