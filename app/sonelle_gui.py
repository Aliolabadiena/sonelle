"""
sonelle_gui.py - the sonelle liquid-glass desktop app (Python front-end).

A frameless pywebview (WebView2) window renders ui/index.html. Each tab is an
xterm.js terminal whose bytes come from a real PowerShell running bin/sonelle.ps1
inside a pseudo-terminal (pywinpty) BEHIND THE SCENES. The routing brain stays in
PowerShell; this layer is purely a beautiful front-end + PTY plumbing.

  python sonelle_gui.py        (normally started for you by bin\\sonelle_gui.ps1)

Threading model (see docs\\ARCHITECTURE.md):
  - main thread        : create_window() + webview.start() (blocks)
  - js_api methods     : each runs on its OWN thread (NOT thread-safe) -> locks
  - one daemon thread  : per PTY, blocking read loop -> run_js push to xterm.js
"""
import os
import sys
import re
import json
import queue
import base64
import threading
import subprocess

# Blocking PTY reads (the default). We read in dedicated daemon threads, so blocking
# is exactly what we want. Must be set before the first PtyProcess is constructed.
os.environ.setdefault("PYWINPTY_BLOCK", "1")

import webview
from winpty import PtyProcess

APP_DIR = os.path.dirname(os.path.abspath(__file__))
ENGINE = os.path.dirname(APP_DIR)
UI_INDEX = os.path.join(APP_DIR, "ui", "index.html")
SONELLE_PS1 = os.path.join(ENGINE, "bin", "sonelle.ps1")
CREATE_NO_WINDOW = 0x08000000


def _powershell_exe():
    import shutil
    exe = shutil.which("powershell.exe")
    if exe:
        return exe
    sysroot = os.environ.get("SystemRoot", r"C:\Windows")
    return os.path.join(sysroot, "System32", "WindowsPowerShell", "v1.0", "powershell.exe")


PS = _powershell_exe()


class Session:
    __slots__ = ("tab_id", "proc", "thread", "lock", "alive")

    def __init__(self, tab_id, proc):
        self.tab_id = tab_id
        self.proc = proc
        self.thread = None
        self.lock = threading.Lock()  # serialize write/resize/close on this PTY
        self.alive = True


class SessionManager:
    """Owns the PTY sessions. One Session + one daemon read-thread per tab."""

    def __init__(self):
        self.window = None
        self._sessions = {}
        self._g = threading.Lock()      # guards _sessions + _n
        self._n = 0
        # _window_open is an unsynchronized best-effort latch (bool access is atomic); the real
        # safety net is the try/except in _emit. Read-threads never touch the WebView2 control
        # directly - they enqueue, and ONE pusher thread coalesces and calls run_js.
        self._window_open = True
        self._q = queue.Queue()
        self._pusher = threading.Thread(target=self._push_loop, daemon=True)
        self._pusher.start()

    # --- the single choke-point that actually calls into WebView2 (race-safe) ---
    def _emit(self, script):
        if not self._window_open or self.window is None:
            return
        try:
            self.window.run_js(script)   # fire-and-forget; lower overhead than evaluate_js
        except Exception:
            # window torn down between the check and the call -> swallow + latch closed
            self._window_open = False

    # --- one pusher thread: drains the queue, coalesces consecutive same-tab output into one
    #     run_js per batch (decouples blocking reads from the UI round-trip) ---
    def _push_loop(self):
        while True:
            item = self._q.get()              # blocks; no idle spin
            if item is None:
                break                          # poison pill on shutdown
            batch = [item]
            try:
                while True:
                    batch.append(self._q.get_nowait())
            except queue.Empty:
                pass
            if not self._window_open:
                continue
            i, n = 0, len(batch)
            while i < n:
                kind, tab, payload = batch[i]
                if kind == "out":
                    parts = [payload]
                    j = i + 1
                    while j < n and batch[j][0] == "out" and batch[j][1] == tab:
                        parts.append(batch[j][2]); j += 1
                    b64 = base64.b64encode("".join(parts).encode("utf-8", "replace")).decode("ascii")
                    self._emit("window.__ptyOutput('%s','%s')" % (tab, b64))
                    i = j
                else:  # "exit"
                    self._emit("window.__ptyExit('%s',%s)" % (tab, payload))
                    i += 1

    def new_tab(self, project=None, cols=80, rows=24):
        try:
            cols = int(cols) or 80
            rows = int(rows) or 24
        except Exception:
            cols, rows = 80, 24
        if not os.path.isfile(SONELLE_PS1):
            return {"ok": False, "error": "sonelle.ps1 not found at %s" % SONELLE_PS1}
        try:
            proc = PtyProcess.spawn(
                [PS, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", SONELLE_PS1, "-Bare"],
                dimensions=(rows, cols),     # (rows, cols); -Bare = no welcome, chat-feel
                cwd=ENGINE,
                env=os.environ.copy(),
            )
        except Exception as e:
            return {"ok": False, "error": str(e)}
        with self._g:
            self._n += 1
            tab_id = "t%d" % self._n
            sess = Session(tab_id, proc)
            self._sessions[tab_id] = sess
        t = threading.Thread(target=self._pump, args=(sess,), daemon=True)
        sess.thread = t
        t.start()
        return {"ok": True, "tabId": tab_id, "title": (project or "sonelle"),
                "cols": cols, "rows": rows}

    def _pump(self, sess):
        # Blocking read loop. read() returns decoded str with VT/ANSI intact; we just enqueue it
        # (the pusher thread coalesces + base64s + calls run_js, so reads never block on the UI).
        proc = sess.proc
        tab = sess.tab_id
        try:
            while True:
                try:
                    data = proc.read(4096)
                except EOFError:
                    break
                except Exception:
                    break
                if data:
                    self._q.put(("out", tab, data))
        finally:
            sess.alive = False
            code = None
            try:
                code = proc.exitstatus
            except Exception:
                code = None
            self._q.put(("exit", tab, "null" if code is None else int(code)))

    def send_input(self, tab_id, data):
        sess = self._sessions.get(tab_id)
        if not sess or data is None:
            return None
        with sess.lock:
            try:
                sess.proc.write(data)   # verbatim: '\r', '\x03', '\x1b[A', ...
            except Exception:
                pass
        return None

    def resize(self, tab_id, cols, rows):
        sess = self._sessions.get(tab_id)
        if not sess:
            return None
        try:
            cols = int(cols)
            rows = int(rows)
        except Exception:
            return None
        if cols < 1 or rows < 1:
            return None
        with sess.lock:
            try:
                sess.proc.setwinsize(rows, cols)   # NOTE: (rows, cols)
            except Exception:
                pass
        return None

    def close_tab(self, tab_id):
        with self._g:
            sess = self._sessions.pop(tab_id, None)
        if sess:
            self._kill(sess)
        return {"ok": True}

    def _kill(self, sess):
        pid = None
        with sess.lock:
            try:
                pid = sess.proc.pid
            except Exception:
                pid = None
        # Kill the WHOLE tree FIRST, while the head PowerShell is still alive and owns its children
        # (ConPTY has no signal tree). Doing this before close() avoids orphaned claude/node and a
        # PID-reuse race where taskkill /T could hit an innocent reused PID.
        if pid:
            try:
                subprocess.run(
                    ["taskkill", "/F", "/T", "/PID", str(pid)],
                    creationflags=CREATE_NO_WINDOW,
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                )
            except Exception:
                pass
        with sess.lock:
            try:
                sess.proc.close(force=True)
            except Exception:
                pass

    def shutdown_all(self):
        self._window_open = False
        with self._g:
            sessions = list(self._sessions.values())
            self._sessions.clear()
        for sess in sessions:
            self._kill(sess)
        try:
            self._q.put_nowait(None)   # stop the pusher thread
        except Exception:
            pass


def _hub_dir():
    # Mirror sonelle.ps1: hub comes from sonelle.config.json, else the engine root.
    cfg = os.path.join(ENGINE, "sonelle.config.json")
    hub = ENGINE
    if os.path.isfile(cfg):
        try:
            with open(cfg, "r", encoding="utf-8") as f:
                c = json.load(f)
            h = c.get("hub")
            if h and h != ".":
                hub = h if os.path.isabs(h) else os.path.join(ENGINE, h)
        except Exception:
            pass
    return hub


def list_projects():
    """Read-only: parse the hub PROJECTS.md table into [{shortcut,name,path}]."""
    pf = os.path.join(_hub_dir(), "PROJECTS.md")
    out = []
    if not os.path.isfile(pf):
        return out
    try:
        with open(pf, "r", encoding="utf-8") as f:
            lines = f.read().splitlines()
    except Exception:
        return out
    for ln in lines:
        s = ln.strip()
        if not s.startswith("|"):
            continue
        cells = [c.strip() for c in s.strip("|").split("|")]
        if len(cells) < 3:
            continue
        short = cells[0]
        if not re.match(r"^[a-z0-9_]+$", short):   # skips header + |---| separator rows
            continue
        out.append({"shortcut": short, "name": cells[1], "path": cells[2]})
    return out


class Api:
    # NOTE: only the public (no-underscore) METHODS below are exposed to JS. Data attributes
    # are underscore-prefixed so pywebview does NOT introspect/serialize them - walking the
    # pywebview Window's WinForms `.native` graph off the UI thread floods stderr and recurses.
    def __init__(self):
        self._window = None
        self._sm = SessionManager()
        self._max = False

    # terminals / tabs
    def new_tab(self, project=None, cols=80, rows=24):
        return self._sm.new_tab(project, cols, rows)

    def send_input(self, tabId, data):
        return self._sm.send_input(tabId, data)

    def resize(self, tabId, cols, rows):
        return self._sm.resize(tabId, cols, rows)

    def close_tab(self, tabId):
        return self._sm.close_tab(tabId)

    def list_projects(self):
        return list_projects()

    # window controls (no built-in JS window API -> expose wrappers)
    def win_minimize(self):
        try:
            self._window.minimize()
        except Exception:
            pass
        return None

    def win_toggle_max(self):
        try:
            if self._max:
                self._window.restore()
                self._max = False
            else:
                self._window.maximize()
                self._max = True
        except Exception:
            pass
        return {"maximized": self._max}

    def win_close(self):
        try:
            self._window.destroy()
        except Exception:
            pass
        return None


def main():
    if not os.path.isfile(SONELLE_PS1):
        sys.stderr.write("sonelle.ps1 not found at %s\n" % SONELLE_PS1)
    debug = bool(os.environ.get("SONELLE_DEBUG"))
    api = Api()
    win = webview.create_window(
        "sonelle",
        UI_INDEX,                       # entry file -> internal HTTP server (relative assets work)
        js_api=api,
        width=1120, height=720, min_size=(660, 420),
        frameless=True, easy_drag=False, resizable=True,
        background_color="#0f0b16",     # ignored by WebView2; harmless
    )
    api._window = win
    api._sm.window = win

    def _on_closing():
        try:
            api._sm.shutdown_all()
        except Exception:
            pass
        return True

    win.events.closing += _on_closing
    # keep the maximize/restore glyph in sync when the OS maximizes us (Aero Snap, double-click drag)
    def _on_max(*a):
        api._max = True
    def _on_restore(*a):
        api._max = False
    try:
        win.events.maximized += _on_max
    except Exception:
        pass
    try:
        win.events.restored += _on_restore
    except Exception:
        pass
    webview.start(gui="edgechromium", debug=debug)


if __name__ == "__main__":
    main()
