"""
narrator.py - sonelle's voice narrator (the "she reports her progress out loud" feature).

Data source = Claude Code HOOKS, not screen-scraping. When the glass app launches `claude` it
adds `--settings <generated file>`; that file (written by setup() here) wires app\narrator\
narrate_hook.ps1 to claude's PreToolUse / PostToolUse / Notification / Stop / UserPromptSubmit
events. Each event is appended as one JSON line to a per-tab events file. A TabNarrator tails that
file and turns events into humanised, FIRST-PERSON lines that name what she's actually on - the
file, the command, the task - so they have DIRECTION ("ok, digging into narrator.py", "running
selftest to see if it holds", "all green, 42 passing, nice!", "that's me done") rather than a
flat "she is reading the code". Each line is built by composition (a varied opener + a phrase from
a sizable pool + a reaction on results) so it never loops like a robot, rate-limited to the
important beats; when the tab's voice toggle is on it speaks each via tts.synth and pushes
(report-box text + audio) to the UI.

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

# Lines are COMPOSED, not enumerated, so they have variety + direction without a giant table:
#   subject  -> what she's on right now: the file basename (read/edit), the command (bash), the
#               grep pattern, the task (see _subject); slotted into a phrase via the "{s}" token, or a
#               per-category fallback noun (_GENERIC) when there's nothing concrete.
#   DISPLAY  -> the little report box under the gif: SHORT but it NAMES the thing ("reading
#               narrator.py <3") and keeps a cute ASCII tag (:*, <3, :), :o). Pure ASCII.
#   SPEAK    -> tts: FIRST PERSON with energy - a varied opener (_OPEN) + the phrase + a reaction on
#               results (_REACT), e.g. "ok, digging into narrator.py" / "all green, 42 passing,
#               nice!". Never an emoticon (the report tags are display-only; _clean_speech also guards).
# Each category gives a POOL of display phrases ("d") and speak phrases ("s") so she never loops. The
# assistant name (when set) is spoken as a sign-on on the bookends only (start / idle), not every line.
#
# Four reporting STYLES (the settings panel picks one via narrator.style): warm (default), terse,
# hacker, bubbly. Each is a full variant of the phrase set + its own opener/reaction energy. PINK
# categories (start/waiting/idle/green/error/answer) talk TO you; WHITE ones are the play-by-play.

# opener fragments prefixed to a SPOKEN line for energy/variety (some empty = no opener that time).
_OPEN = {
    "warm":   ["ok, ", "alright, ", "right, ", "ok-- ", "", "", "cool, "],
    "terse":  [""],
    "hacker": ["", "", "ok, "],
    "bubbly": ["ooh, ", "okay, ", "yay, ", "alright, ", "right, ", "okok, "],
}

# a little reaction tacked onto a spoken test RESULT (the "emotion" on the milestone).
_REACT = {
    "warm":   {"green": ["nice!", "lovely.", "let's go.", "happy with that."],
               "error": ["let me look.", "on it.", "i'll dig in.", "okay, fixable."]},
    "terse":  {"green": [""], "error": [""]},
    "hacker": {"green": ["clean.", "green."], "error": ["patching.", "on it."]},
    "bubbly": {"green": ["woo!", "yesss!", "amazing!"], "error": ["eep!", "we got this!", "no worries, on it!"]},
}

# fallback noun for "{s}" when there's no concrete subject (only used by phrases that contain {s}).
_GENERIC = {
    "reading": "the code", "editing": "the file", "researching": "that", "running": "the command",
    "testing": "the tests", "helper": "this", "working": "it", "start": "it",
}
# Each style maps a category -> {"d": [display phrases], "s": [speak phrases]}. "{s}" is the subject
# slot (file/command/...); "{n}" is a count (green/error). Pools are several deep so she varies.
_STYLES = {
    "warm": {
        "reading":    {"d": ["reading {s} <3", "in {s} :)", "skimming {s}", "peeking at {s} :o"],
                       "s": ["reading through {s}", "digging into {s}", "having a look at {s}",
                             "getting my head around {s}"]},
        "editing":    {"d": ["editing {s} :)", "reworking {s} <3", "tweaking {s}", "on {s} :*"],
                       "s": ["reworking {s}", "editing {s}", "rewriting a bit of {s}",
                             "making some changes in {s}"]},
        "researching":{"d": ["looking up {s} :o", "researching {s}"],
                       "s": ["looking into {s} online", "researching {s}", "digging around online for {s}"]},
        "running":    {"d": ["running {s} :)", "kicking off {s}"],
                       "s": ["running {s}", "kicking off {s}", "firing off {s}"]},
        "testing":    {"d": ["testing {s} :o", "running the tests :o"],
                       "s": ["running the tests", "kicking off the tests", "running {s} to see if it holds"]},
        "committing": {"d": ["committing :)", "writing the commit <3"],
                       "s": ["committing this", "writing up the commit", "saving this down"]},
        "pushing":    {"d": ["shipping it <3", "pushing up :)"],
                       "s": ["pushing this up", "shipping it to the repo", "sending it up"]},
        "helper":     {"d": ["got a helper :o", "sidekick on {s}"],
                       "s": ["bringing in a helper for {s}", "spinning up a sidekick",
                             "handing {s} off to a helper"]},
        "working":    {"d": ["working <3", "on it :)"],
                       "s": ["working on {s}", "getting into {s}", "on {s} now"]},
        "waiting":    {"d": ["got a q for you :o", "need you :o"],
                       "s": ["i've got a question for you", "i need a quick steer from you",
                             "can you take a look when you get a sec"]},
        "idle":       {"d": ["all done <3", "wrapped up :)", "that's me :)"],
                       "s": ["all done", "that's me done", "wrapped up, all set"]},
        "start":      {"d": ["on it <3", "got it :)", "starting in :)"],
                       "s": ["on it now", "starting in on {s}", "getting going on {s}", "on it"]},
        "green":      {"d": ["all green, {n} :)", "{n} passing <3", "green! {n} :)"],
                       "s": ["tests are green, {n} passing", "all green, {n} passing",
                             "{n} tests passing, all green"]},
        "error":      {"d": ["{n} failing :o", "uh oh, {n} :(", "{n} to fix :/"],
                       "s": ["we've got {n} failing", "{n} tests came back failing", "{n} failing, not yet"]},
    },
    "terse": {
        "reading":    {"d": ["read {s}"], "s": ["reading {s}"]},
        "editing":    {"d": ["edit {s}"], "s": ["editing {s}"]},
        "researching":{"d": ["research"], "s": ["researching {s}"]},
        "running":    {"d": ["run {s}"], "s": ["running {s}"]},
        "testing":    {"d": ["test"], "s": ["running tests"]},
        "committing": {"d": ["commit"], "s": ["committing"]},
        "pushing":    {"d": ["push"], "s": ["pushing"]},
        "helper":     {"d": ["helper"], "s": ["launched a helper"]},
        "working":    {"d": ["working"], "s": ["working"]},
        "waiting":    {"d": ["question"], "s": ["i have a question"]},
        "idle":       {"d": ["done"], "s": ["done"]},
        "start":      {"d": ["start"], "s": ["starting"]},
        "green":      {"d": ["{n} pass"], "s": ["{n} passing"]},
        "error":      {"d": ["{n} fail"], "s": ["{n} failing"]},
    },
    "hacker": {
        "reading":    {"d": ["> read {s}"], "s": ["scanning {s}", "reading {s}"]},
        "editing":    {"d": ["> patch {s}"], "s": ["patching {s}", "rewriting {s}"]},
        "researching":{"d": ["> recon"], "s": ["running recon on {s}", "digging for {s}"]},
        "running":    {"d": ["> exec {s}"], "s": ["executing {s}", "running {s}"]},
        "testing":    {"d": ["> test"], "s": ["running the test suite", "firing the tests"]},
        "committing": {"d": ["> commit"], "s": ["committing the work"]},
        "pushing":    {"d": ["> push"], "s": ["pushing to the remote"]},
        "helper":     {"d": ["> fork"], "s": ["forking a sub-agent", "spinning up an agent"]},
        "working":    {"d": ["> busy"], "s": ["working the problem"]},
        "waiting":    {"d": ["> input?"], "s": ["i need your input"]},
        "idle":       {"d": ["> idle"], "s": ["idle, standing by"]},
        "start":      {"d": ["> init"], "s": ["spinning up on {s}", "booting into {s}"]},
        "green":      {"d": ["> PASS {n}"], "s": ["all {n} green", "{n} passing"]},
        "error":      {"d": ["> FAIL {n}"], "s": ["{n} failing", "{n} red"]},
    },
    "bubbly": {
        "reading":    {"d": ["reading {s}!! :D"], "s": ["reading through {s}", "soaking up {s}"]},
        "editing":    {"d": ["editing {s}!! <3"], "s": ["happily reworking {s}", "editing {s}"]},
        "researching":{"d": ["googling!! :o"], "s": ["looking up {s}", "researching {s}"]},
        "running":    {"d": ["running {s}!! :D"], "s": ["running {s}", "kicking off {s}"]},
        "testing":    {"d": ["testing!! :o"], "s": ["running the tests, fingers crossed", "running {s}"]},
        "committing": {"d": ["saving!! <3"], "s": ["committing this", "saving it all down"]},
        "pushing":    {"d": ["shipping!! :D"], "s": ["shipping it up", "pushing it live"]},
        "helper":     {"d": ["helper!! :o"], "s": ["calling in a little helper", "spinning up a buddy for {s}"]},
        "working":    {"d": ["working!! <3"], "s": ["working on {s}", "getting into {s}"]},
        "waiting":    {"d": ["psst, q!! :o"], "s": ["i've got a quick question for you",
                                                    "ooh, can you take a look"]},
        "idle":       {"d": ["all done!! <3"], "s": ["all wrapped up", "all done, yay"]},
        "start":      {"d": ["yay, on it!! <3"], "s": ["on it", "starting in on {s}", "getting going on {s}"]},
        "green":      {"d": ["all green!! {n} :D"], "s": ["all {n} passing", "the tests are green, {n} passing"]},
        "error":      {"d": ["oh no!! {n} :o"], "s": ["{n} are failing", "we've got {n} to fix"]},
    },
}
_DEFAULT_STYLE = "warm"

def _styleset(style):
    return _STYLES.get(style) or _STYLES[_DEFAULT_STYLE]


def _short(s, n=40):
    """Squash any text into a short, single-line, pure-ASCII subject fit to drop into a phrase."""
    import re
    s = str(s or "")
    s = "".join(ch if 32 <= ord(ch) < 127 else " " for ch in s)   # printable ASCII only
    s = re.sub(r"\s+", " ", s).strip().strip("'\"`")
    if len(s) > n:
        s = s[:n].rstrip() + "..."
    return s


def _subject(tool, ti):
    """The thing she's on right now, as a short label: the file (read/edit), the grep pattern, the
    command (bash), the task (Task), the query (web). "" when there's nothing concrete to name."""
    t = (tool or "").lower()
    ti = ti or {}

    def _base(p):
        p = str(p or "").replace("\\", "/").rstrip("/")
        return _short(os.path.basename(p), 28)

    if t in ("read", "notebookread", "ls"):
        return _base(ti.get("file_path") or ti.get("path") or ti.get("notebook_path") or "")
    if t in ("edit", "write", "multiedit", "notebookedit", "update", "create", "applypatch"):
        return _base(ti.get("file_path") or ti.get("path") or ti.get("notebook_path") or "")
    if t == "grep":
        return _short(ti.get("pattern") or "", 28)
    if t == "glob":
        return _short(ti.get("pattern") or "", 28)
    if t in _WEB:
        return _short(ti.get("query") or ti.get("url") or "", 36)
    if t == "task":
        return _short(ti.get("description") or ti.get("prompt") or "", 36)
    if t == "bash":
        return _bash_subject(ti.get("command") or "")
    return ""


def _fill(t, s, n):
    """Slot the subject ({s}) and count ({n}) into a phrase template."""
    t = str(t)
    if "{s}" in t:
        t = t.replace("{s}", s)
    if "{n}" in t:
        t = t.replace("{n}", "" if n is None else str(n))
    return t


def _squash(s):
    while "  " in s:
        s = s.replace("  ", " ")
    return s.strip()


def _render(style, cat, subject, n=None):
    """Compose (display, speak) for one category: pick a display + speak phrase from the pool, fill
    the subject/count, add a spoken opener for energy, and a reaction on a test result."""
    spec = _styleset(style).get(cat) or _STYLES[_DEFAULT_STYLE].get(cat)
    if not spec:
        return None
    s = subject or _GENERIC.get(cat, "")
    try:
        disp = random.choice(spec["d"])
        say = random.choice(spec["s"])
    except Exception:
        disp, say = spec["d"][0], spec["s"][0]
    display = _squash(_fill(disp, s, n))
    speak = _fill(say, s, n)
    opens = _OPEN.get(style) or _OPEN[_DEFAULT_STYLE]
    if opens:
        speak = random.choice(opens) + speak
    if cat in ("green", "error"):
        rs = (_REACT.get(style) or _REACT[_DEFAULT_STYLE]).get(cat) or [""]
        r = random.choice(rs)
        if r:
            sep = " " if speak[-1:] in ".!?," else ", "   # don't run the reaction into the clause
            speak = speak + sep + r
    return [display, _squash(speak)]


def _milestone(style, cat, n):
    """A count-based milestone (green/error) - just a subject-less _render."""
    return _render(style, cat, "", n)


def _decorate(out, cat, nm, important):
    """Finish a rendered (display, speak) pair: add the assistant-name sign-on on the bookends
    (start / idle) only, and attach the pink/white kind + the importance flag."""
    if not out:
        return None
    display, speak = out[0], out[1]
    if nm and cat in ("start", "idle"):
        speak = "%s here-- %s" % (nm, speak)
    return (display, speak, _kind(cat), important)


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


def _bash_subject(cmd):
    """A short friendly name for the command she's running ("selftest", "the tests", or the program
    name) - the direction for a bash line. "" for pushes (the phrase already says "the repo")."""
    c = str(cmd or "").strip()
    if not c:
        return ""
    low = c.lower()
    if "selftest" in low:
        return "selftest"
    if any(k in low for k in ("pytest", "jest", "vitest", "unittest", "npm test",
                              "npm run test", "go test", "cargo test", "dotnet test", "rspec")):
        return "the tests"
    if "git" in low and "commit" in low:
        return "the commit"
    if "git" in low and "push" in low:
        return ""
    parts = c.split()
    tok = parts[0] if parts else ""
    return _short(os.path.basename(tok.replace("\\", "/")), 24)


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

    DISPLAY = the short report-box line (cute ASCII tag, names the file/command); SPEAK = the
    first-person spoken line with the same direction + a bit of energy (opener + reaction). `kind`
    is 'voice' (pink: she's texting you) or 'status' (white: the play-by-play). `cfg` carries the
    reporting `style` + assistant `name`; `state` carries the ambient de-dup memory, keyed on
    category+subject so switching files re-announces but a run of the SAME file collapses."""
    cfg = cfg or {}
    style = cfg.get("style") or _DEFAULT_STYLE
    nm = cfg.get("name") or "sonelle"
    nm = nm if (nm and nm != "sonelle") else None      # a custom name -> spoken as a sign-on

    ename = ev.get("hook_event_name") or ev.get("hookEventName") or ""
    tool = ev.get("tool_name") or ev.get("toolName") or ""
    ti = ev.get("tool_input") or ev.get("toolInput") or {}

    cat = None
    subj = ""
    if ename == "UserPromptSubmit":
        p = ev.get("prompt") or ev.get("user_prompt") or ""
        state["last_prompt"] = p
        # a short/targeted question or confirmation ("sounds good?", "what's my ss show?") -> don't
        # announce "getting to work"; she'll just answer it out loud when she's done (Stop, below).
        if len(p.strip()) <= 140 or p.strip().endswith("?"):
            return None
        cat = "start"
        subj = _short(p, 48)                           # a snippet of the task = direction on the opener
    elif ename == "Stop":
        # Claude Code hands us her final reply in last_assistant_message. When it's short, REPORT IT -
        # this is how she answers simple/targeted questions; the box shows it and (voice on) speaks it.
        msg = _clean_speech(ev.get("last_assistant_message") or ev.get("lastAssistantMessage"))
        prompt = (state.get("last_prompt") or "").strip()
        cap = 400 if prompt.endswith("?") else 260
        if msg and len(msg) <= cap:
            state["last_cat"] = "answer"
            state["last_key"] = "answer"
            state["last_cat_ts"] = time.monotonic()
            return (msg, msg, "voice", True)           # her own words -> box display + speech
        cat = "idle"
    elif ename == "Notification":
        cat = "waiting"
    elif ename == "SubagentStop":
        return None  # too granular to narrate
    elif ename == "PreToolUse":
        cat = _pre_category(tool, ti)
        subj = _subject(tool, ti)                      # the file/command/task she's on -> direction
    elif ename == "PostToolUse":
        pr = _post_line(tool, ev.get("tool_response") or ev.get("toolResponse"))
        if not pr:
            return None
        cat, n = pr
        state["last_cat"] = cat
        state["last_key"] = cat
        state["last_cat_ts"] = time.monotonic()
        return _decorate(_milestone(style, cat, n), cat, nm, True)
    else:
        return None

    if cat is None:
        return None
    important = cat in _IMPORTANT

    now = time.monotonic()
    key = cat + "|" + (subj or "")
    if not important:
        # collapse a run of the SAME activity on the SAME thing (don't say "reading x" twenty times),
        # but a new file/command (a new key) re-announces - that's the direction the report carries.
        if key == state.get("last_key") and (now - state.get("last_cat_ts", 0.0)) < AMBIENT_REPEAT:
            return None

    out = _render(style, cat, subj, None)
    if not out:
        return None
    state["last_cat"] = cat
    state["last_key"] = key
    state["last_cat_ts"] = now
    return _decorate(out, cat, nm, important)


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
