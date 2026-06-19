# ARCHITECTURE — how sonelle fits together

## Engine vs your data
- **sonelle (this repo) = the ENGINE.** Reusable mechanism: dispatcher, registry format,
  templates, scaffold/heal/improve tools, the terminal. **No personal data.**
- **Your projects = separate.** Created *using* sonelle, but they are not sonelle. Their code,
  state (TODO/ledger), and memory live in your own hub, never in this repo.

A fresh clone on any machine + your Claude login = a working, empty workspace you can
create new projects in.

## The flow
```
you ── "myproj: do X" ──> sonelle.ps1 (terminal)
                             │  reads PROJECTS.md (registry, single source of truth)
                             ├─ found ──> cd <code path> ──> claude  (your subscription)
                             └─ not found ──> offer :new ──> new_project.ps1 ──> registry row
```
- `CLAUDE.md` = the dispatcher a Claude session reads to orient (read state first, never guess).
- `PROJECTS.md` = the only roster. Rows added via `new_project.ps1`, not by hand.
- Per project: `<SHORT>_TODO.txt` (tasks), `_<short>_run_STATUS.md` (ledger),
  `memory/project_<short>.md` (summary), `<code path>\CLAUDE.md` (project rules).

## The three capabilities
- **Scaffold** (`tools\new_project.ps1`) — real mechanism: one command, consistent skeleton + registry row.
- **Heal** (`tools\doctor.ps1` + `docs\HEAL.md`) — doctor DETECTS; the fix loop is Claude-driven (manual).
  A project's checks live in `<code path>\sonelle.check.ps1`; absent it, "heal" = "code path exists".
- **Self-improve** (`tools\log_lesson.ps1` + `docs\SELF_IMPROVE.md`) — capture tool; the recall/reflect
  loop is a discipline, not engine-enforced. Two stores: **personal / per-project** lessons go to the
  gitignored hub `memory\` (default), while **generic, cross-project** lessons ship IN the engine at
  `knowledge\` (`log_lesson.ps1 -Shared`, indexed by `knowledge\INDEX.md`) - public, ASCII, no personal
  data - so a fresh clone already carries them. The SessionStart hook recalls both.

## CLAUDE.md load behavior (important)
Claude Code auto-loads `CLAUDE.md` from the working directory up to the project/git root - NOT from an
arbitrary engine path. The terminal `Push-Location`s into the PROJECT's code dir before calling `claude`,
so the working session loads the PROJECT's `CLAUDE.md` (the per-project pointer that carries the
read-state-first + end-of-task ritual), not this engine's dispatcher. That is intended: the terminal
already did the routing. The engine root `CLAUDE.md` is the dispatcher for a human who opens `claude`
directly inside the sonelle folder. If `-Hub` points at a workspace that has its OWN `CLAUDE.md`, that file
governs its sessions - sonelle's routing only reads `PROJECTS.md` and does not merge hub-level dispatchers.
For *developing the engine itself*, the terminal's `:dev` command (or the grammar with the engine's own
name as the shortcode - `<engine-name>: <prompt>`, derived from the engine folder name and special-cased
in `Route`, never the registry) opens a session in the engine root seeded with `docs\DEVELOPING.md` (the
engine-dev invariants), which overrides the dispatcher framing of the root `CLAUDE.md` for that one session.

## Multi-instance (lanes)
`bin\sonelle_team.ps1 <proj> -Lanes a,b,c` runs up to 5 parallel `claude` sessions on one project, each a
LANE scoped to a disjoint workstream (e.g. bugs / concepts / website). They do NOT share live memory -
they coordinate via a shared board at `<code>\.sonelle\lanes\` (one status file per lane) + DISJOINT file
ownership (critical when the project has no git merge safety). Windows Terminal tabs if `wt` is
installed, else separate PowerShell windows. `:team` / `:status` in the terminal wrap it. Hard cap 5;
>3 warns about rate limits (N lanes ~= Nx subscription usage).

## The app (multi-terminal shell)
`bin\sonelle_app.ps1` is a single Claude-styled WINDOW that hosts many sonelle terminals as tabs -
the GUI counterpart to a lone `sonelle.ps1` console. It is self-contained: NO Windows Terminal
dependency. Each tab embeds a REAL console: the app `Start-Process`es `powershell -File bin\sonelle.ps1`
(minimized), polls for its `MainWindowHandle`, then Win32-`SetParent`s that window into a WinForms panel
after stripping the caption/border style bits (`Sonelle.Win::Embed`); on resize it `MoveWindow`s the
active console to fill (`::Fit`). So every tab IS the ordinary terminal - same grammar, same routing,
same `claude` hand-off - just several at once in one frame. `+ new` opens a tab; `[x]` closes one and
`taskkill /T /F`s that terminal's process tree. Launch it with `:app` (from a terminal); `make_launcher.ps1`
makes the primary `sonelle` shortcut open the app by default (`-Terminal` for a single console).
Robustness: consoles attach ASYNCHRONOUSLY via a `Forms.Timer` (poll for `MainWindowHandle`, then embed) -
no blocking and no `DoEvents` re-entrancy, so closing/clicking during attach can never touch a disposed
control; every handler is try/catch-wrapped, runtime `$ErrorActionPreference` is `Continue`, and the app
kills only the PIDs it spawned. Built on WinForms rather than WPF on purpose: every WinForms control has a
native HWND, so hosting an external console is robust; WPF would need a fragile `WindowsFormsHost` bridge
for the identical result. The lanes feature (above) is for parallel `claude` sessions on ONE project;
the app is for running several INDEPENDENT terminals (any projects, or `:dev`) side by side.
selftest builds the whole UI + interop headlessly via `sonelle_app.ps1 -SelfTest` (no window, no spawn).
This WinForms host is now the **classic fallback** (`:app-classic`); the default `:app` opens the glass app below.

## The glass app (Python front-end - default)
`app\` is the default desktop app: a frameless **Python** window (`pywebview`, backed by the Edge
**WebView2** runtime) rendering `app\ui\` (HTML/CSS/JS) with a muted dark-purple **liquid-glass** UI.
Each tab is an **xterm.js** terminal; behind it, `app\sonelle_gui.py` spawns `powershell -File bin\sonelle.ps1`
in a **pseudo-terminal** (`pywinpty`) and pumps bytes both ways - so the terminal brain runs hidden and
the interactive `claude` TUI renders in-app. One PTY + one daemon read-thread per tab.
- **Renderer:** xterm.js uses the **WebGL** addon (GPU), not its default DOM renderer. Over a transparent
  (glass) background the DOM renderer ghosts/flickers and mashes glyphs together (a transparent "space"
  cell never paints over the glyph beneath it); WebGL clears every cell each frame, so text stays crisp.
  It falls back to the DOM renderer if a GL context can't be created. The font is **Cascadia Mono** first
  (no ligatures - a ligature font overlaps glyphs in xterm's one-glyph-per-cell grid), and resize fits are
  debounced (`scheduleFit`, one per frame) so window drags don't churn the terminal. The pane pulls its
  RIGHT padding in and gives the xterm grid a right gutter (`.pane .xterm{ padding-right }`) so the
  scrollbar rides the box edge in its own lane instead of overlapping the last column of glyphs (FitAddon
  subtracts that element padding when it computes columns).
- **Tab names:** each terminal tab is labelled with a plain incrementing number (`1`, `2`, `3`, ...) in
  the order it was opened. `nextTabName()` in `app.js` bumps a monotonic `tabSeq` counter, so closing a
  tab never renumbers the rest. A project-named tab keeps the project name.
- **Contract:** JS->Python via `window.pywebview.api.{new_tab, send_input, resize, close_tab, set_narration,
  get_settings, save_settings, upload_mascot, list_projects, save_paste_image, win_minimize, win_toggle_max,
  win_close}`; Python->JS via fire-and-forget `run_js` calling `window.__ptyOutput(tabId, base64Bytes)` /
  `window.__ptyExit(tabId, code)` / `window.__narrate(tabId, display, kind, mime, audioB64)` (the `display`
  text lands in the mascot's report box, `kind` = `"voice"` pink / `"status"` white). `tabId` is
  Python-owned. `new_tab` also returns a `session` number (the spoken "session N" opener).
- **Window move:** the frameless window drags from the title bar via pywebview's `.pywebview-drag-region`
  class (WebView2 ignores Electron's `-webkit-app-region`); an `app.js` mousedown guard cancels the drag
  over `.nodrag` controls so buttons/tabs/the input still click. The taskbar/window icon is `sonelle.ico`
  (window icon via `icon=` on `webview.start()`; the taskbar also needs an explicit AppUserModelID - below).
- **Paste images:** Ctrl+V in the composer saves the clipboard image to a temp file (`save_paste_image`,
  NOT the repo) and inserts an `@"<path>"` token; the terminal then routes it to claude like `:attach`/`@path`.
- **Threading:** `webview.start()` on the main thread; js_api methods each run on their own thread
  (shared session dict under a lock); read-threads push through ONE guard that checks a `_window_open`
  flag + try/except so a torn-down window can never crash them. On close: terminate+close each PTY then
  `taskkill /F /T` its pid (ConPTY has no signal tree, so claude/node grandchildren would orphan).
- **Glass:** WebView2 **cannot** be transparent on Windows, so the glass is self-contained - an in-app
  gradient + translucent `backdrop-filter` panels - identical on Win10/11 (no OS acrylic dependency).
- **Brand loop (the mascot + her reporter):** `#brandloop` is a WRAPPER (`app\ui\index.html`) holding a
  **report box** (`#loop-report`) ABOVE a `.gifwrap` (the looping mascot gif `app\ui\brandloop.gif` + a
  control row: **padlock . mute . session label**). The report sits above the gif so the gif stays in its
  home corner and the box expands upward. It STARTS LOW in the bottom-right corner (`right:30px;
  bottom:8px`, off the scrollbar lane) with **physics** (`pointer-events:auto`, `cursor:grab`):
  `wireBrandloopDrag` lets you drag it; release it mid-motion and `throwLoop` flings it with
  inertia/friction, BOUNCING off the window edges, then 30s later `returnLoopHome` drifts it home (a
  control/report click doesn't start a drag). The **report-arrow** (`toggleReport`) opens/closes the
  report (so does **V** when not typing); the **padlock** (`toggleLoopLock`) ONLY pins it (no bounce / no
  drift) and has nothing to do with the report - the box shows on `.brandloop.reportopen` alone (the old
  `.brandloop.locked .report` coupling was dropped in v1.34); **mute** mirrors that
  tab's voice toggle; the **session label** is low-contrast `--moody` text. **Per-tab gif state** lives in
  `entry.gif = {left, top, locked, reportOpen, report[]}` and is saved/applied on every tab switch
  (`applyGifState`). The pane reserves an 88px bottom band so the grid stops ABOVE the gif, `#bar` a right
  band so the command bar parks to its LEFT, and the report box uses the terminal's scrollbar styling.
  `draggable="false"` kills the browser image-drag; the gif self-animates at half speed.
- **Reporting (the report bug fix):** narration is NO LONGER typed into the terminal - claude's TUI runs
  on the alternate screen and repaints over injected lines, so they vanished. `window.__narrate` now
  appends the `display` text to that tab's report log (`reportLine` -> `renderReport` into `#loop-report`,
  pink `.rline.voice` / white `.rline.status`) and plays the audio through ONE **global serialized queue**
  (`enqueueAudio`/`pumpAudio`) so two sessions never talk over each other. (An earlier desktop pop-out
  overlay was dropped on purpose - the reporter lives in-app.)
- **Settings (the gear):** a titlebar gear (before the `_ O X` controls) opens a glass panel (`#settings`):
  **20 palettes** (`app\ui\palettes.js`; `applyPalette` writes the `:root` CSS vars + every xterm theme,
  live), the **assistant name** (display-only - the narrator reads it, the engine self-dev shortcode is
  untouched), **upload-your-own mascot** (`upload_mascot` stages it to `%LOCALAPPDATA%\sonelle`, never the
  repo), the **reporting style** (warm/terse/hacker/bubbly -> `narrator.style`), **other-voices instructions**
  (display only), and the **model split** - the **orchestrator** model + effort (`models.orchestrator`/
  `orchestratorEffort` -> claude's `--model`/`--effort`) and a separate **code-writer** model
  (`models.codeWriter`, `inherit` = same) that `bin\sonelle.ps1` exports as `CLAUDE_CODE_SUBAGENT_MODEL`
  so claude's file-editing subagents run on their own model. `save_settings` merges into
  `sonelle.config.json`; palette/name are also cached in `localStorage`. The model block is **live**:
  `RefreshOrch` re-reads it before every `claude` launch, so a settings change takes effect on the NEXT
  prompt without restarting the tab (the config file - overridable via `$env:SONELLE_CONFIG` - is the
  channel). A claude session already mid-run keeps the model/effort it launched with (only Claude Code's
  own in-session effort control can change that); permission mode stays on its `-Yolo`/`:yolo` overrides.
- **Launch + deps:** `bin\sonelle_gui.ps1` bootstraps a local `.venv` (`pywebview` + `pywinpty`, pinned in
  `app\requirements.txt`) on first run, then starts the GUI with `pythonw` (no console). The window
  passes `icon=assets\icon\sonelle.ico` to `webview.start()` so the window's `Form.Icon` is the sonelle
  mark. That alone fixes only the (hidden, frameless) title bar; the **taskbar** button still grouped
  under `pythonw.exe` and showed its Python feather. So at startup the backend calls
  `SetCurrentProcessExplicitAppUserModelID("sonelle.glass.app")` (Windows-only) to claim its own taskbar
  identity, detaching the button from `pythonw` so it adopts the sonelle icon. `xterm.js`, `addon-fit`,
  and `addon-webgl` are vendored under `app\ui\vendor\` (MIT, offline; versions paired - see its NOTICE).
  selftest section 8e checks the files, the JS<->Python contract markers, the launcher wiring, and
  `py_compile`s the backend; section 1 excludes `.venv`.
- **Skip permission prompts (yolo):** by default `claude` asks before risky actions. Set `SONELLE_YOLO=1`
  and the glass app spawns the terminal with `-Yolo`, which runs `claude --permission-mode bypassPermissions`
  so it never asks. In any terminal you can also toggle it live with `:yolo` (or `:yolo on|off`), or set it
  permanently via `sonelle.config.json` -> `models.orchestratorPermissionMode: "bypassPermissions"`.
- **PreToolUse guard + slash commands + inherent altitude (v1.36):** because yolo removes claude's own
  permission prompts, the engine and every scaffolded project ship a **PreToolUse guard hook**
  (`.claude\hooks\pretooluse_guard.ps1`, wired in `.claude\settings.json`) - claude runs it BEFORE every
  `Write`/`Edit`/`Bash` and it EXITS 2 to block the call (feeding the reason back to claude) or 0 to allow,
  failing open on any error so it can never break a session. The engine guard enforces the house rule
  (pure-ASCII `.ps1`) and invariant #4 (no hub state / `new_project` / plain `log_lesson` at the engine
  root) and blocks force-push; the project guard blocks force-push and is yours to extend. **Slash
  commands** (`.claude\commands\`: `/selftest /heal /ship /ritual`) turn the rituals into one keystroke.
  And `bin\sonelle.ps1` appends a one-line **operating policy** to every project/engine session via
  `--append-system-prompt`, so claude decides the workflow from the task itself: delegate hard / multi-file
  work to subagents, verify a change against the right check, heal a failure, and run the end-of-task ritual
  when done - scaling down to nothing on a one-liner. The `general:` lane gets a minimal no-state variant.
  selftest 8h (+ 5d) cover all of it.
- **Onboarding primer, :adopt, and the general lane (v1.37):** each glass-app tab runs `-Bare`, which now
  greets you with a short no-claude primer (how to make a project, adopt an existing one, run a task,
  connect claude) instead of a blank prompt; `help`/`?` shows the commands without ever calling claude.
  **`:adopt <path>`** brings an existing, non-sonelle codebase into the workflow: it scaffolds the skeleton
  over it (backing up any `CLAUDE.md`/`.claude\` to `*.pre-sonelle.bak` first), then asks claude to adapt
  the generic scaffold to the real code - best-effort, and honest that a very different structure may need
  a manual fix. **`general: <prompt>`** is a one-off lane for a quick question or throwaway task: it runs in
  a neutral scratch dir (`%TEMP%\sonelle_general`) with no project, no registry row, and no saved state, so
  it never clutters your real projects' memory or docs.
- **Voice narrator (per-tab):** each tab pill carries its OWN speaker toggle (built in `app.js`
  `makeTabEl`; the mascot's mute button mirrors it), so you mute the boring research sessions and keep
  the important ones talking. When a tab's voice is on, sonelle **reports in the box under the mascot**
  (NOT the terminal - see "Reporting" above) in two colours: **pink** when she's talking to YOU and
  **soft white** for the play-by-play. Each event is **dual-rendered** with **direction + variety**:
  `build_line` COMPOSES `(display, speak, kind, important)` instead of reading a fixed table - `_subject`
  pulls what she's on right now (the file basename, the bash command, the grep pattern, the task) into the
  phrase, so the short cute `display` line NAMES it ("reading narrator.py <3", ASCII tag kept) and the
  `speak` line is **first-person with energy** (a varied opener + a phrase from a pool + a reaction on a
  result, e.g. "all green, 42 passing, nice!"). De-dup is keyed on category+subject so a new file
  re-announces but a repeat collapses; a custom name is spoken as a sign-on on the bookends.
  `_clean_speech`/`_strip_emoticons` keep emoticons out of speech. The data source is **Claude Code
  hooks**, not screen scraping: the app
  launches `claude` with `--settings <generated file>` so its `PreToolUse`/`PostToolUse`/`Notification`/
  `Stop`/`UserPromptSubmit` events are appended (by `app\narrate_hook.ps1`, via the per-tab env var
  `SONELLE_NARRATE_FILE`) to a per-tab JSONL file. A per-tab `TabNarrator` (`app\narrator.py`) tails it,
  maps each event to a rate-limited `(display, speak)` tagged `voice`/`status`, picks the phrase set for
  the configured **reporting style** (warm/terse/hacker/bubbly), and - voice on - synthesizes speech
  (`app\tts.py`) and pushes via `window.__narrate`; audio plays through the global serialized queue, and
  with 2+ live narrators the spoken opener says "session N, ...". **Voice engine:** the primary is **Kokoro** - a modern neural voice that runs LOCALLY
  (ONNX, free/no-key, fully offline). The voice MODEL is **vendored in the repo** at `app\voice\` (the
  ~88 MB int8 build + voice pack, small enough for plain git) - **no download**, it ships with sonelle;
  only the small `kokoro-onnx` runtime installs via pip (best-effort, `app\requirements-voice.txt`).
  `edge-tts` (cloud neural) then Windows **SAPI** (offline) are automatic fallbacks, so she always
  talks. Default voice `af_heart` at 0.95 speed (`narrator.voice`/`speed`). **Safety gate:**
  `narrator.setup()` first probes that `claude` advertises `--settings` (`claude --help`); only then does
  it publish `SONELLE_NARRATE_SETTINGS` for `bin\sonelle.ps1` to attach `--settings`. So an older/absent
  claude is never handed an unknown flag - narration just stays dormant and the app is unaffected. Off by
  default; `sonelle.config.json` -> `narrator` sets `enabled`, `voice`, `speed`, `rate`, `pitch`, `engine`.
  JS<->Python adds one method (`set_narration`) and one push (`__narrate`, now carrying `kind`).

## Billing
The terminal hands prompts to `claude` (Claude Code), which runs on your Claude Pro/Max
subscription — no API key for personal use. (Shipping this as a product to *other* users
would require API-key auth; personal use does not.)

## House rules
- PowerShell scripts are **pure ASCII** (PS 5.1 misreads non-ASCII in a no-BOM `.ps1`).
  Build glyphs at runtime via `[char]` codepoints.
- Registry rows have a fixed column shape — `new_project.ps1` writes them; don't hand-edit.
