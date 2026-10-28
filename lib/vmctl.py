#!/usr/bin/env python3
"""Drive the macOS VM through QEMU's QMP socket: screenshots, mouse and keyboard.
Runs inside the macbox container (`macbox screenshot/click/type/key/scroll/wait` call it).
VM_QMP is the QMP socket; VM_RESOLUTION_FILE holds the screen size clicks are scaled to.

  vmctl.py shot OUT.png            screendump of the guest display (PNG)
  vmctl.py click X Y [right|double] click at guest pixel X,Y (the screen's current size)
  vmctl.py move X Y
  vmctl.py scroll X Y N            wheel N notches (negative = up)
  vmctl.py type TEXT               type text (US layout)
  vmctl.py wait SECONDS [OUT.png]  wait until the screen changes (>1%), then shot
  vmctl.py key COMBO...            e.g. ret, tab, esc, meta-space, meta-q, ctrl-c
"""
import json, os, socket, sys, time

SOCK = os.environ["VM_QMP"]
SHOTS = os.environ.get("VM_SHOTS", "/tmp")
def _res():  # the guest's screen size ($MACBOX_HOME/run/resolution), 1920x1080 by default
    try: return tuple(int(v) for v in open(os.environ["VM_RESOLUTION_FILE"]).read().strip().split("x"))
    except Exception: return (1920, 1080)
W, H = int(os.environ.get("VM_W", _res()[0])), int(os.environ.get("VM_H", _res()[1]))

class QMP:
    def __init__(self):
        for _ in range(50):
            try:
                self.s = socket.socket(socket.AF_UNIX); self.s.connect(SOCK); break
            except OSError:
                time.sleep(0.1)
        self.f = self.s.makefile("rw")
        json.loads(self.f.readline())
        self.cmd("qmp_capabilities")
    def cmd(self, name, **args):
        self.f.write(json.dumps({"execute": name, "arguments": args} if args else {"execute": name}) + "\n"); self.f.flush()
        while True:
            r = json.loads(self.f.readline())
            if "return" in r: return r["return"]
            if "error" in r: raise SystemExit(f"{name}: {r['error']}")
    def ev(self, events):
        self.cmd("input-send-event", events=events)

def absm(x, y):
    return [{"type": "abs", "data": {"axis": "x", "value": int(x * 32767 / (W - 1))}},
            {"type": "abs", "data": {"axis": "y", "value": int(y * 32767 / (H - 1))}}]

def btn(b, down):
    return [{"type": "btn", "data": {"down": down, "button": b}}]

SHIFTED = {'~': '`', '!': '1', '@': '2', '#': '3', '$': '4', '%': '5', '^': '6', '&': '7', '*': '8', '(': '9', ')': '0',
           '_': 'minus', '+': 'equal', '{': 'bracket_left', '}': 'bracket_right', '|': 'backslash', ':': 'semicolon',
           '"': 'apostrophe', '<': 'comma', '>': 'dot', '?': 'slash'}
PLAIN = {'`': 'grave_accent', '-': 'minus', '=': 'equal', '[': 'bracket_left', ']': 'bracket_right', '\\': 'backslash',
         ';': 'semicolon', "'": 'apostrophe', ',': 'comma', '.': 'dot', '/': 'slash', ' ': 'spc', '\n': 'ret', '\t': 'tab'}
ALIAS = {'meta': 'meta_l', 'cmd': 'meta_l', 'ctrl': 'ctrl', 'alt': 'alt', 'opt': 'alt', 'shift': 'shift', 'enter': 'ret',
         'backspace': 'backspace', 'del': 'delete', 'up': 'up', 'down': 'down', 'left': 'left', 'right': 'right', 'esc': 'esc', 'space': 'spc'}

def keys_for(ch):
    if ch.isalpha() and ch.isascii():
        return (['shift'] if ch.isupper() else []) + [ch.lower()]
    if ch.isdigit(): return [ch]
    if ch in PLAIN: return [PLAIN[ch]]
    if ch in SHIFTED:
        k = SHIFTED[ch]; return ['shift', PLAIN.get(k, k)]
    raise SystemExit(f"cannot type {ch!r}")

def press(q, names):
    ks = [{"type": "qcode", "data": ALIAS.get(n, n)} for n in names]
    q.ev([{"type": "key", "data": {"down": True, "key": k}} for k in ks]); time.sleep(0.03)
    q.ev([{"type": "key", "data": {"down": False, "key": k}} for k in reversed(ks)]); time.sleep(0.03)

def main():
    a = sys.argv[1:]
    if not a: print(__doc__); return
    q = QMP(); c = a[0]
    if c == "shot":
        q.cmd("screendump", filename=os.path.abspath(a[1]), format="png")
    elif c in ("click", "move"):
        x, y = float(a[1]), float(a[2]); q.ev(absm(x, y)); time.sleep(0.05)
        if c == "click":
            b = "right" if "right" in a[3:] else "left"
            for _ in range(2 if "double" in a[3:] else 1):
                q.ev(btn(b, True)); time.sleep(0.06); q.ev(btn(b, False)); time.sleep(0.06)
    elif c == "scroll":
        q.ev(absm(float(a[1]), float(a[2])))
        n = int(a[3]); b = "wheel-up" if n < 0 else "wheel-down"
        for _ in range(abs(n)):
            q.ev(btn(b, True)); q.ev(btn(b, False)); time.sleep(0.03)
    elif c == "type":
        # "type -" reads the text from stdin, so secrets stay out of process arguments.
        text = sys.stdin.read().rstrip("\n") if a[1:] == ["-"] else " ".join(a[1:])
        for ch in text: press(q, keys_for(ch))
    elif c == "key":
        for combo in a[1:]: press(q, combo.split("-")); time.sleep(0.1)
    elif c == "wait":
        # Wait (up to N s) until the screen differs from now by more than a spinner's worth.
        tmp = os.path.join(SHOTS, ".w.ppm")
        def grab():
            q.cmd("screendump", filename=tmp)
            d = open(tmp, "rb").read(); return d[d.index(b"255\n") + 4:]
        base = grab(); end = time.time() + float(a[1]); n = 0
        while time.time() < end:
            time.sleep(3); cur = grab()
            n = sum(1 for i in range(0, len(cur), 48) if cur[i] != base[i])
            if n > len(cur) // 48 // 100: break
        print("changed" if n > len(base) // 48 // 100 else "timeout")
        if len(a) > 2: q.cmd("screendump", filename=os.path.abspath(a[2]), format="png")
    else:
        raise SystemExit(__doc__)

main()
