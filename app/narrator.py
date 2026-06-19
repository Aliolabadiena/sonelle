"""
narrator.py - sonelle's voice narrator (the "she reports her progress out loud" feature).

Data source = Claude Code HOOKS, not screen-scraping. When the glass app launches `claude` it
adds `--settings <generated file>`; that file (written by setup() here) wires app\narrator\
narrate_hook.ps1 to claude's PreToolUse / PostToolUse / Notification / Stop / UserPromptSubmit
events. Each event is appended as one JSON line to a per-tab events file. A TabNarrator tails that
file, turns events into humanised THIRD-PERSON status lines ("sonelle is reading the code...",
"ouch - she ran into 7 problems.", "tests came back green - 1666 passing.", "she's idle now."),
rate-limits them to the important beats, and - when the tab's voice toggle is on - speaks each via
tts.synth and pushes (text + audio) to the UI, which renders the line in bold pink.

Safety: if `claude` doesn't advertise `--settings`, setup() reports disabled and the app NEVER
passes the flag - so a working app can't be broken by this feature; narration just stays dormant.
Pure ASCII for consistency with the rest of the engine.
"""
import os
import json
import time
import queue
import random
import tempfile
import threading
import subprocess

try:
    import tts
except Exception:
    tts = None

_CREATE_NO_WINDOW = 0x08000000

# pacing
MIN_GAP = 1.6          # seconds between two spoken lines (no overlap / no spam)
AMBIENT_REPEAT = 12.0  # don't repeat the same ambient category within this many seconds

# event categories that are always worth a word (vs. ambient ones we collapse)
_IMPORTANT = {"start", "idle", "waiting", "testing", "committing", "pushing", "green", "error"}

# Two voices on screen (see app.js): PINK is sonelle texting YOU - the openers, the check-ins, the
# milestones, her actual answers; WHITE is the quiet play-by-play of what she's doing right now.
# Anything not listed here is a white "status" line.
_VOICE_CATS = {"start", "idle", "waiting", "green", "error", "answer"}


def _kind(cat):
    return "voice" if cat in _VOICE_CATS else "status"

# read tools / edit tools (Claude Code tool names)
_READ = {"read", "glob", "grep", "ls", "notebookread"}
_EDIT = {"edit", "write", "multiedit", "notebookedit", "update", "create", "applypatch"}
_WEB = {"webfetch", "websearch"}

# TWO renderings per event (the reporter "style split"):
#   - DISPLAY -> the little report box under the gif: SHORT and to the point, but alive with a cute
#     ASCII tag (:*, <3, :), :o). Pure ASCII so the .py stays ASCII-clean.
#   - SPEAK   -> tts: a touch fuller, natural, THIRD person ("sonelle is reading the code"), and NEVER
#     contains an emoticon (the report-box tags are stripped from speech by _clean_speech anyway).
# Each category is a list of [display, speak] pairs so she doesn't loop like a robot. The DISPLAY name
# "sonelle" in a speak line is swapped for the configured assistant name at emit time (see _named).
#
# Four reporting STYLES (the settings panel picks one via narrator.style): warm (default), terse,
# hacker, bubbly. Each is a full variant of the phrase set. PINK categories (start/waiting/idle/green/
# error/answer) talk TO you; WHITE ones (reading/editing/...) are the quiet play-by-play.
_STYLES = {
    "warm": {
        "start":      [["on it <3", "sonelle is on it now"], ["got it :)", "sonelle is getting started"]],
        "reading":    [["reading <3", "sonelle is reading through the code"],
                       ["looking around :)", "sonelle is getting her bearings"]],
        "editing":    [["editing :)", "sonelle is editing the code"],
                       ["tweaking it <3", "sonelle is rewriting a bit of this"]],
        "researching":[["looking it up :o", "sonelle is researching this online"]],
        "running":    [["running it :)", "sonelle is running a command"]],
        "testing":    [["testing :o", "sonelle is running the tests"]],
        "committing": [["committing :)", "sonelle is writing the commit"]],
        "pushing":    [["shipping it <3", "sonelle is pushing it up to the repo"]],
        "helper":     [["little helper :o", "sonelle is spinning up a sidekick"]],
        "working":    [["working <3", "sonelle is working on it"]],
        "waiting":    [["has a question :o", "sonelle has a question for you"]],
        "idle":       [["all done <3", "sonelle is all done now"]],
    },
    "terse": {
        "start":      [["start", "sonelle started"]],
        "reading":    [["reading", "sonelle is reading the code"]],
        "editing":    [["editing", "sonelle is editing"]],
        "researching":[["research", "sonelle is researching"]],
        "running":    [["running", "sonelle is running a command"]],
        "testing":    [["testing", "sonelle is running tests"]],
        "committing": [["commit", "sonelle is committing"]],
        "pushing":    [["push", "sonelle is pushing"]],
        "helper":     [["helper", "sonelle launched a helper"]],
        "working":    [["working", "sonelle is working"]],
        "waiting":    [["question", "sonelle has a question"]],
        "idle":       [["done", "sonelle is done"]],
    },
    "hacker": {
        "start":      [["> init", "sonelle is spinning up"]],
        "reading":    [["> read src", "sonelle is scanning the source"]],
        "editing":    [["> patch", "sonelle is patching the code"]],
        "researching":[["> recon", "sonelle is running recon"]],
        "running":    [["> exec", "sonelle is executing a command"]],
        "testing":    [["> run tests", "sonelle is running the test suite"]],
        "committing": [["> commit", "sonelle is committing the work"]],
        "pushing":    [["> push", "sonelle is pushing to the remote"]],
        "helper":     [["> fork agent", "sonelle forked a sub-agent"]],
        "working":    [["> busy", "sonelle is working the problem"]],
        "waiting":    [["> awaiting input", "sonelle needs your input"]],
        "idle":       [["> idle", "sonelle is idle"]],
    },
    "bubbly": {
        "start":      [["yay, on it!! <3", "sonelle is super on it now"]],
        "reading":    [["reading!! :D", "sonelle is reading all the code"]],
        "editing":    [["editing!! <3", "sonelle is happily editing away"]],
        "researching":[["googling!! :o", "sonelle is looking this all up"]],
        "running":    [["running!! :D", "sonelle is running a command"]],
        "testing":    [["testing!! :o", "sonelle is running the tests, fingers crossed"]],
        "committing": [["saving!! <3", "sonelle is committing this"]],
        "pushing":    [["shipping!! :D", "sonelle is shipping it up, woo"]],
        "helper":     [["helper!! :o", "sonelle called in a little helper"]],
        "working":    [["working!! <3", "sonelle is working on it"]],
        "waiting":    [["psst, question!! :o", "sonelle has a quick question for you"]],
        "idle":       [["all done!! <3", "sonelle is all wrapped up, yay"]],
    },
}
_DEFAULT_STYLE = "warm"

# count-based milestones (test pass/fail) - [display_template, speak_template], one per style. "%s"
# is the count. DISPLAY is short + tagged; SPEAK is natural, third person, no emoticon.
_MILESTONES = {
    "warm":   {"green": ["tests green :)", "the tests came back green, %s passing"],
               "error": ["uh oh :o", "the tests came back failing, %s to fix"]},
    "terse":  {"green": ["%s passing", "tests pass, %s green"],
               "error": ["%s failing", "tests failing, %s broken"]},
    "hacker": {"green": ["> tests PASS", "all tests passed, %s green"],
               "error": ["> tests FAIL", "tests failed, %s failing"]},
    "bubbly": {"green": ["all green!! :D", "the tests are all green, %s passing, yay"],
               "error": ["oh no!! :o", "the tests are failing, %s to fix"]},
}


def _styleset(style):
    return _STYLES.get(style) or _STYLES[_DEFAULT_STYLE]


def _pick(style, cat):
    """Return a [display, speak] pair for this style+category, or None."""
    pool = _styleset(style).get(cat) or _STYLES[_DEFAULT_STYLE].get(cat)
    if not pool:
        return None
    try:
        return list(random.choice(pool))
    except Exception:
        return list(pool[0])


def _milestone(style, cat, n):
    """Return a [display, speak] pair for a count-based milestone (green/error)."""
    m = (_MILESTONES.get(style) or _MILESTONES[_DEFAULT_STYLE]).get(cat)
    if not m:
        m = _MILESTONES[_DEFAULT_STYLE][cat]
    try:
        return [m[0] % n if "%s" in m[0] else m[0], m[1] % n if "%s" in m[1] else m[1]]
    except Exception:
        return [str(cat), str(cat)]


def _strip_emoticons(s):
    """Remove emoticons / kaomoji so the spoken line never vocalizes ':)' or '<3'. The report-box
    DISPLAY text keeps its cute tags; only SPEAK text is run through here."""
    import re
    s = str(s or "")
    s = re.sub(r"</?3", " ", s)                                      # <3 </3 hearts
    s = re.sub(r"[:;=8xX][-^o']?[\)\(\]\[DPpOo3/\\|*]{1,3}", " ", s) # :) ;-) xD :* :o :/ etc.
    s = re.sub(r"[\^>oO][_.\-][\^<oO]", " ", s)                      # ^_^ >_< o_o kaomoji cores
    # drop emoji / pictographs / arrows (>= U+2190) but keep accented Latin letters
    s = "".join(ch if ord(ch) < 0x2190 else " " for ch in s)
    return s


def _clean_speech(s):
    """Flatten an assistant message to plain speakable text: drop markdown noise + emoticons,
    collapse space."""
    import re
    s = str(s or "")
    s = re.sub(r"```.*?```", " ", s, flags=re.S)        # fenced code blocks
    s = re.sub(r"`([^`]*)`", r"\1", s)                  # inline code -> its text
    s = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", s)    # links/images -> the label
    s = re.sub(r"[*_#>|`~]+", " ", s)                   # leftover markdown punctuation
    s = _strip_emoticons(s)                             # never speak ':)' / '<3' / kaomoji
    s = re.sub(r"\s+", " ", s).strip()
    return s


def _bash_category(cmd):
    c = (cmd or "").lower()
    if any(k in c for k in ("selftest", "pytest", "jest", "vitest", "unittest", "go test",
                            "cargo test", "dotnet test", "npm test", "npm run test", "rspec")):
        return "testing"
    if "git" in c and "commit" in c:
        return "committing"
    if "git" in c and "push" in c:
        return "pushing"
    return "running"


def _pre_category(tool, ti):
    t = (tool or "").lower()
    if t in _READ:
        return "reading"
    if t in _EDIT:
        return "editing"
    if t in _WEB:
        return "researching"
    if t == "task":
        return "helper"
    if t == "bash":
        return _bash_category((ti or {}).get("command", ""))
    return "working"


def _post_line(tool, resp):
    """Detect a meaningful command RESULT (test pass/fail counts). Returns (cat, count_str) or None."""
    if (tool or "").lower() != "bash":
        return None
    if isinstance(resp, (dict, list)):
        try:
            resp = json.dumps(resp)
        except Exception:
            resp = str(resp)
    text = str(resp or "")
    low = text.lower()
    import re
    mfail = re.search(r'(\d+)\s+(?:failed|failing|errors?)', low)
    if mfail and int(mfail.group(1)) > 0:
        return ("error", mfail.group(1))
    mpass = re.search(r'(\d+)\s+(?:passed|passing)', low)
    if mpass and int(mpass.group(1)) > 0:
        return ("green", mpass.group(1))
    mratio = re.search(r'\b(\d+)\s*/\s*(\d+)\b', text)
    if mratio and mratio.group(1) == mratio.group(2) and int(mratio.group(2)) > 0:
        return ("green", mratio.group(2))
    return None


def build_line(state, ev, cfg=None):
    """Map one hook event -> (display, speak, kind, important) or None.

    DISPLAY = the short report-box line (with a cute ASCII tag); SPEAK = the natural spoken line
    (third person, no emoticon). `kind` is 'voice' (pink: sonelle texting you) or 'status' (white:
    the play-by-play). `cfg` carries the reporting `style` + assistant `name`; `state` carries the
    ambient de-dup memory."""
    cfg = cfg or {}
    style = cfg.get("style") or _DEFAULT_STYLE
    nm = cfg.get("name") or "sonelle"
    nm = nm if (nm and nm != "sonelle") else None      # only substitute a non-default name

    def _pair(p, cat, important):
        display, speak = p[0], p[1]
        if nm:
            speak = speak.replace("sonelle", nm)       # speak as the chosen assistant name
        return (display, speak, _kind(cat), important)

    ename = ev.get("hook_event_name") or ev.get("hookEventName") or ""
    tool = ev.get("tool_name") or ev.get("toolName") or ""
    ti = ev.get("tool_input") or ev.get("toolInput") or {}

    cat = None
    if ename == "UserPromptSubmit":
        p = ev.get("prompt") or ev.get("user_prompt") or ""
        state["last_prompt"] = p
        # a short/targeted question or confirmation ("sounds good?", "what's my ss show?") -> don't
        # announce "getting to work"; she'll just answer it out loud when she's done (Stop, below).
        if len(p.strip()) <= 140 or p.strip().endswith("?"):
            return None
        cat = "start"
    elif ename == "Stop":
        # Claude Code hands us her final reply in last_assistant_message. When it's short, REPORT IT -
        # this is how she answers simple/targeted questions; the box shows it and (voice on) speaks it.
        msg = _clean_speech(ev.get("last_assistant_message") or ev.get("lastAssistantMessage"))
        prompt = (state.get("last_prompt") or "").strip()
        cap = 400 if prompt.endswith("?") else 260
        if msg and len(msg) <= cap:
            state["last_cat"] = "answer"
            state["last_cat_ts"] = time.monotonic()
            return (msg, msg, "voice", True)           # her own words -> box display + speech
        cat = "idle"
    elif ename == "Notification":
        cat = "waiting"
    elif ename == "SubagentStop":
        return None  # too granular to narrate
    elif ename == "PreToolUse":
        cat = _pre_category(tool, ti)
    elif ename == "PostToolUse":
        pr = _post_line(tool, ev.get("tool_response") or ev.get("toolResponse"))
        if not pr:
            return None
        cat, n = pr
        state["last_cat"] = cat
        state["last_cat_ts"] = time.monotonic()
        return _pair(_milestone(style, cat, n), cat, True)
    else:
        return None

    if cat is None:
        return None
    important = cat in _IMPORTANT

    now = time.monotonic()
    if not important:
        # collapse a run of the same ambient activity (don't say "reading" twenty times)
        if cat == state.get("last_cat") and (now - state.get("last_cat_ts", 0.0)) < AMBIENT_REPEAT:
            return None

    pair = _pick(style, cat)
    if not pair:
        return None
    state["last_cat"] = cat
    state["last_cat_ts"] = now
    return _pair(pair, cat, important)


# ---------------------------------------------------------------------------------------------
# per-tab narrator: tail the events file -> humanise -> (if voice on) speak + push to the UI
# ---------------------------------------------------------------------------------------------
class TabNarrator:
    def __init__(self, tab_id, events_file, emit, voice_cfg, session=0):
        self.tab_id = tab_id
        self.events_file = events_file
        self._emit = emit                 # emit(tab_id, display, kind, mime_or_None, b64_or_None)
        self._cfg = voice_cfg or {}
        self._voice = False
        self._alive = True
        self._session = session           # this tab's session number ("session N" spoken opener)
        self._multi = False               # set by the manager: True when 2+ narrators are live
        self._state = {"last_cat": None, "last_cat_ts": 0.0}
        self._q = queue.Queue(maxsize=8)
        self._last_spoke = 0.0
        self._tail = threading.Thread(target=self._tail_loop, daemon=True)
        self._work = threading.Thread(target=self._work_loop, daemon=True)

    def start(self):
        self._tail.start()
        self._work.start()

    def set_multi(self, on):
        # when more than one tab is narrating, spoken VOICE lines get a "session N, ..." prefix so you
        # can tell which session is talking (the report boxes / gif labels already show it visually).
        self._multi = bool(on)

    def set_voice(self, on):
        on = bool(on)
        self._voice = on
        if not on:
            # go quiet at once: drop anything queued
            try:
                while True:
                    self._q.get_nowait()
            except queue.Empty:
                pass

    def close(self):
        self._alive = False
        try:
            self._q.put_nowait(None)
        except Exception:
            pass

    def _tail_loop(self):
        pos = 0
        buf = ""
        while self._alive:
            try:
                if os.path.isfile(self.events_file):
                    size = os.path.getsize(self.events_file)
                    if size < pos:
                        pos = 0          # file rotated/truncated -> reread from start
                    if size > pos:
                        with open(self.events_file, "r", encoding="utf-8-sig", errors="replace") as f:
                            f.seek(pos)
                            buf += f.read()
                            pos = f.tell()
                        while "\n" in buf:
                            line, buf = buf.split("\n", 1)
                            self._on_line(line)
            except Exception:
                pass
            time.sleep(0.25)

    def _on_line(self, line):
        line = line.strip()
        if not line:
            return
        try:
            ev = json.loads(line)
        except Exception:
            return
        if not isinstance(ev, dict):
            return
        out = build_line(self._state, ev, self._cfg)
        if not out:
            return
        try:
            self._q.put_nowait(out)
        except queue.Full:
            try:
                self._q.get_nowait()       # drop the oldest pending to make room
            except Exception:
                pass
            try:
                self._q.put_nowait(out)
            except Exception:
                pass

    def _work_loop(self):
        while True:
            item = self._q.get()
            if item is None:
                break
            if not self._alive:
                continue
            display, speak, kind, important = item
            # an ambient line that's already superseded by a newer queued line: skip it
            if not important and not self._q.empty():
                continue
            if not self._voice:
                continue
            now = time.monotonic()
            gap = now - self._last_spoke
            if gap < MIN_GAP:
                time.sleep(MIN_GAP - gap)
            if not self._voice or not self._alive:
                continue
            mime = None
            b64 = None
            spk = speak
            if self._multi and kind == "voice" and self._session:
                spk = "session %d, %s" % (self._session, speak)          # announce which session speaks
            try:
                res = tts.synth_b64(spk, self._cfg) if tts else None      # SPEAK (no emoticon) -> audio
                if res:
                    mime, b64 = res
            except Exception:
                mime = None
                b64 = None
            self._last_spoke = time.monotonic()
            try:
                self._emit(self.tab_id, display, kind, mime, b64)        # DISPLAY (cute) -> report box
            except Exception:
                pass


# ---------------------------------------------------------------------------------------------
# setup: write the hooks settings file claude will load, gated on `--settings` actually existing
# ---------------------------------------------------------------------------------------------
_SUPPORT_CACHE = None


def _ps_exe():
    import shutil
    exe = shutil.which("powershell.exe")
    if exe:
        return exe
    sysroot = os.environ.get("SystemRoot", r"C:\Windows")
    return os.path.join(sysroot, "System32", "WindowsPowerShell", "v1.0", "powershell.exe")


def events_dir():
    return os.path.join(tempfile.gettempdir(), "sonelle_narrate")


def events_file_for(tab_id):
    safe = "".join(ch for ch in str(tab_id) if ch.isalnum())
    return os.path.join(events_dir(), "ev_%d_%s.jsonl" % (os.getpid(), safe))


def _read_cfg(engine_dir):
    # Default to the local Kokoro neural voice (good, offline once downloaded); edge/sapi are the
    # fallbacks inside tts.synth. "voice" is the Kokoro voice id; "speed" is its rate (1.0 = normal).
    cfg = {"enabled": True, "engine": "kokoro", "voice": "af_heart", "speed": 0.95,
           "rate": "+0%", "pitch": "+0Hz", "style": _DEFAULT_STYLE, "name": "sonelle"}
    path = os.path.join(engine_dir, "sonelle.config.json")
    if os.path.isfile(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                c = json.load(f)
            n = c.get("narrator") or {}
            for k in ("enabled", "engine", "voice", "speed", "rate", "pitch", "style", "name"):
                if k in n:
                    cfg[k] = n[k]
            # the assistant DISPLAY name may also live at the top level (the settings panel writes it
            # there so the terminal-launched narrator picks it up); top level wins if present.
            an = c.get("assistantName")
            if an:
                cfg["name"] = an
        except Exception:
            pass
    return cfg


def _claude_supports_settings():
    """Probe `claude --help` once for the `--settings` flag. We only ever inject narration when
    it's clearly supported, so an older/absent claude can never have the flag forced on it."""
    global _SUPPORT_CACHE
    if _SUPPORT_CACHE is not None:
        return _SUPPORT_CACHE
    ok = False
    try:
        import shutil
        exe = shutil.which("claude")
        if exe:
            out = subprocess.run(
                '"%s" --help' % exe, shell=True, timeout=12,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                creationflags=_CREATE_NO_WINDOW,
            )
            blob = (out.stdout or b"").decode("utf-8", "replace")
            ok = "--settings" in blob
    except Exception:
        ok = False
    _SUPPORT_CACHE = ok
    return ok


def _write_hooks_settings(engine_dir, out_dir):
    hook = os.path.join(engine_dir, "app", "narrate_hook.ps1")
    cmd = '"%s" -NoProfile -ExecutionPolicy Bypass -File "%s"' % (_ps_exe(), hook)
    h = [{"type": "command", "command": cmd, "timeout": 10}]
    tool_entry = [{"matcher": "*", "hooks": h}]   # tool-scoped events take a matcher
    plain_entry = [{"hooks": h}]                  # lifecycle events do not
    settings = {"hooks": {
        "PreToolUse": tool_entry,
        "PostToolUse": tool_entry,
        "Notification": plain_entry,
        "Stop": plain_entry,
        "UserPromptSubmit": plain_entry,
        "SubagentStop": plain_entry,
    }}
    path = os.path.join(out_dir, "hooks.settings.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(settings, f)
    return path


def setup(engine_dir):
    """Prepare narration. Returns {enabled, settings_path, voice_cfg}. Never raises."""
    info = {"enabled": False, "settings_path": None, "voice_cfg": {}}
    try:
        cfg = _read_cfg(engine_dir)
        info["voice_cfg"] = cfg
        if not cfg.get("enabled", True):
            return info
        if os.environ.get("SONELLE_NARRATE") == "0":
            return info
        if not _claude_supports_settings():
            return info
        d = events_dir()
        os.makedirs(d, exist_ok=True)
        info["settings_path"] = _write_hooks_settings(engine_dir, d)
        info["enabled"] = True
    except Exception:
        info["enabled"] = False
        info["settings_path"] = None
    return info
