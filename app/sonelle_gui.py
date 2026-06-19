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
import tempfile
import threading
import subprocess

# Blocking PTY reads (the default). We read in dedicated daemon threads, so blocking
# is exactly what we want. Must be set before the first PtyProcess is constructed.
os.environ.setdefault("PYWINPTY_BLOCK", "1")

import webview
from winpty import PtyProcess

# Optional voice narrator (app\narrator.py + app\tts.py). Wrapped so any problem in it degrades
# gracefully to "no narration" rather than breaking the app.
try:
    import narrator
except Exception:
    narrator = None

APP_DIR = os.path.dirname(os.path.abspath(__file__))
ENGINE = os.path.dirname(APP_DIR)
UI_INDEX = os.path.join(APP_DIR, "ui", "index.html")
SONELLE_PS1 = os.path.join(ENGINE, "bin", "sonelle.ps1")
# Window/taskbar icon. Without this, pywebview's winforms backend extracts the icon from
# sys.executable (pythonw.exe) and the running app shows the generic Python feather - this
# brands it as sonelle instead (matching the launcher .lnk and the classic WinForms host).
ICON_ICO = os.path.join(ENGINE, "assets", "icon", "sonelle.ico")
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
        self._narr = {}                                      # tab_id -> narrator.TabNarrator
        self._narr_info = {"enabled": False, "voice_cfg": {}}  # set from narrator.setup() in main()

    def set_narration_setup(self, info):
        self._narr_info = info or {"enabled": False, "voice_cfg": {}}

    # the narrator worker threads call this to push a humanised line (+ optional audio) to the UI.
    # kind is "voice" (pink: sonelle texting you) or "status" (white: the play-by-play); the front
    # end types it straight into the terminal in that colour.
    def _narrate_emit(self, tab_id, text, kind, mime, b64):
        self._emit("window.__narrate(%s,%s,%s,%s,%s)" % (
            json.dumps(tab_id), json.dumps(text), json.dumps(kind or "status"),
            json.dumps(mime) if mime else "null",
            json.dumps(b64) if b64 else "null"))

    def set_narration(self, tab_id, on):
        tn = self._narr.get(tab_id)
        if not tn:
            return {"ok": True, "available": False, "on": False}
        try:
            tn.set_voice(bool(on))
        except Exception:
            pass
        return {"ok": True, "available": True, "on": bool(on)}

    def _close_narr(self, tab_id):
        tn = self._narr.pop(tab_id, None)
        if tn:
            try:
                tn.close()
            except Exception:
                pass

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
            poisoned = False
            try:
                while True:
                    nxt = self._q.get_nowait()
                    if nxt is None:            # poison pill drained mid-batch: finish this batch, then stop
                        poisoned = True
                        break
                    batch.append(nxt)
            except queue.Empty:
                pass
            if self._window_open:
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
            if poisoned:
                break

    def new_tab(self, project=None, cols=80, rows=24):
        try:
            cols = int(cols) or 80
            rows = int(rows) or 24
        except Exception:
            cols, rows = 80, 24
        if not os.path.isfile(SONELLE_PS1):
            return {"ok": False, "error": "sonelle.ps1 not found at %s" % SONELLE_PS1}
        # Allocate the tab id BEFORE spawning so we can name this tab's narration events file and put
        # it in the child's environment - claude (launched by the child) must see SONELLE_NARRATE_FILE
        # when it fires its hooks. SONELLE_NARRATE_SETTINGS is already in os.environ (set in main()).
        with self._g:
            self._n += 1
            tab_id = "t%d" % self._n
        env = os.environ.copy()
        events_file = None
        if self._narr_info.get("enabled") and narrator is not None:
            try:
                events_file = narrator.events_file_for(tab_id)
                os.makedirs(os.path.dirname(events_file), exist_ok=True)
                open(events_file, "w").close()    # fresh file so the tail starts clean
                env["SONELLE_NARRATE_FILE"] = events_file
            except Exception:
                events_file = None
        ps_args = [PS, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", SONELLE_PS1, "-Bare"]
        # SONELLE_YOLO=1 -> launch the terminal in -Yolo so claude skips permission prompts. (sonelle.ps1
        # also reads the env var directly, but passing the flag keeps the spawned contract explicit.)
        if os.environ.get("SONELLE_YOLO"):
            ps_args.append("-Yolo")
        try:
            proc = PtyProcess.spawn(
                ps_args,
                dimensions=(rows, cols),     # (rows, cols); -Bare = no welcome, chat-feel
                cwd=ENGINE,
                env=env,
            )
        except Exception as e:
            return {"ok": False, "error": str(e)}
        sess = Session(tab_id, proc)
        with self._g:
            self._sessions[tab_id] = sess
        if events_file is not None:
            try:
                tn = narrator.TabNarrator(tab_id, events_file, self._narrate_emit,
                                          self._narr_info.get("voice_cfg") or {})
                tn.start()
                self._narr[tab_id] = tn
            except Exception:
                pass
        t = threading.Thread(target=self._pump, args=(sess,), daemon=True)
        sess.thread = t
        t.start()
        return {"ok": True, "tabId": tab_id, "title": (project or "sonelle"),
                "cols": cols, "rows": rows, "narration": bool(events_file is not None)}

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
        self._close_narr(tab_id)
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
            narrs = list(self._narr.values())
            self._narr.clear()
        for tn in narrs:
            try:
                tn.close()
            except Exception:
                pass
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


def parse_projects(pf):
    """The ONE Python registry parser: parse a PROJECTS.md file into [{shortcut,name,path}].
    Mirrors tools/_registry.ps1 Get-SonelleProjects exactly - selftest (section Q1) asserts the
    PowerShell and Python parsers agree on the same registry, so they can never drift. Do not add a
    second ad-hoc registry parse anywhere (selftest Q2 greps for one)."""
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
        if short == "shortcode":                   # skip a lower-cased header row (mirrors _registry.ps1)
            continue
        out.append({"shortcut": short, "name": cells[1], "path": cells[2]})
    return out


def list_projects():
    """Read-only: parse the hub PROJECTS.md table into [{shortcut,name,path}]."""
    return parse_projects(os.path.join(_hub_dir(), "PROJECTS.md"))


# --- pasted-image staging (Ctrl+V in the composer) -------------------------------------------
# Pasted clipboard images are written to a temp dir (NOT the repo - they may be personal data and
# must never be committed). The JS side then inserts an @"<path>" token into the composer; the
# terminal (bin\sonelle.ps1) extracts that inline path and tells claude to read it, so the image
# enters claude's context - exactly the path :attach / @path already use.
_PASTE_LOCK = threading.Lock()
_PASTE_N = 0
_PASTE_EXTS = (".png", ".jpg", ".jpeg", ".gif", ".bmp", ".webp")


def save_paste_image(b64, ext=".png"):
    """Decode a base64 clipboard image, write it to a temp file, return {ok, path}."""
    try:
        raw = base64.b64decode(b64 or "")
    except Exception:
        return {"ok": False, "error": "bad image data"}
    if not raw:
        return {"ok": False, "error": "empty image"}
    e = (ext or ".png").lower()
    if not e.startswith("."):
        e = "." + e
    if e == ".jpeg":
        e = ".jpg"
    if e not in _PASTE_EXTS:
        e = ".png"
    d = os.path.join(tempfile.gettempdir(), "sonelle_paste")
    try:
        os.makedirs(d, exist_ok=True)
    except Exception:
        d = tempfile.gettempdir()
    global _PASTE_N
    with _PASTE_LOCK:
        _PASTE_N += 1
        n = _PASTE_N
    path = os.path.join(d, "paste_%d_%d%s" % (os.getpid(), n, e))
    try:
        with open(path, "wb") as f:
            f.write(raw)
    except Exception as ex:
        return {"ok": False, "error": str(ex)}
    return {"ok": True, "path": path}


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

    def set_narration(self, tabId, on):
        # turn a tab's voice narrator on/off (the titlebar speaker toggle)
        return self._sm.set_narration(tabId, on)

    def list_projects(self):
        return list_projects()

    def save_paste_image(self, b64, ext=".png"):
        return save_paste_image(b64, ext)

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


def _set_taskbar_identity():
    # Windows groups taskbar buttons by AppUserModelID. With none set, our window is grouped
    # under the host pythonw.exe and the taskbar shows ITS Python-feather icon - even though
    # pywebview sets the window's Form.Icon to sonelle.ico (that only fixes the title bar, which
    # is hidden here since the window is frameless). Claiming our own AppUserModelID detaches the
    # taskbar button from pythonw so it adopts the window's sonelle icon. Must run before any
    # window exists. Windows-only; a no-op (swallowed) elsewhere.
    if sys.platform != "win32":
        return
    try:
        import ctypes
        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID("sonelle.glass.app")
    except Exception:
        pass


def main():
    if not os.path.isfile(SONELLE_PS1):
        sys.stderr.write("sonelle.ps1 not found at %s\n" % SONELLE_PS1)
    _set_taskbar_identity()
    debug = bool(os.environ.get("SONELLE_DEBUG"))
    api = Api()
    # Voice narrator: write the hooks settings file and, ONLY if `claude` supports `--settings`,
    # publish its path so bin\sonelle.ps1 attaches it. If unsupported the flag is never passed, so
    # narration simply stays dormant and the app is unaffected.
    if narrator is not None:
        try:
            info = narrator.setup(ENGINE)
            api._sm.set_narration_setup(info)
            if info.get("enabled") and info.get("settings_path"):
                os.environ["SONELLE_NARRATE_SETTINGS"] = info["settings_path"]
                if debug:
                    sys.stderr.write("sonelle: voice narrator enabled\n")
            elif debug:
                sys.stderr.write("sonelle: voice narrator inactive (claude --settings not detected)\n")
        except Exception:
            pass
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
    # icon= brands the window/taskbar as sonelle; pywebview's winforms backend applies it
    # (Icon(path) when the file exists, else it would fall back to pythonw.exe's icon).
    start_kwargs = {"gui": "edgechromium", "debug": debug}
    if os.path.isfile(ICON_ICO):
        start_kwargs["icon"] = ICON_ICO
    webview.start(**start_kwargs)


if __name__ == "__main__":
    main()
