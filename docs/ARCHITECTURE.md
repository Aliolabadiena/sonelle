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
  loop is a discipline, not engine-enforced.

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
- **Contract:** JS->Python via `window.pywebview.api.{new_tab, send_input, resize, close_tab, list_projects,
  save_paste_image, win_minimize, win_toggle_max, win_close}`; Python->JS via fire-and-forget `run_js` calling
  `window.__ptyOutput(tabId, base64Bytes)` / `window.__ptyExit(tabId, code)`. `tabId` is Python-owned.
- **Window move:** the frameless window drags from the title bar via pywebview's `.pywebview-drag-region`
  class (WebView2 ignores Electron's `-webkit-app-region`); an `app.js` mousedown guard cancels the drag
  over `.nodrag` controls so buttons/tabs/the input still click. The taskbar/window icon is `sonelle.ico`.
- **Paste images:** Ctrl+V in the composer saves the clipboard image to a temp file (`save_paste_image`,
  NOT the repo) and inserts an `@"<path>"` token; the terminal then routes it to claude like `:attach`/`@path`.
- **Threading:** `webview.start()` on the main thread; js_api methods each run on their own thread
  (shared session dict under a lock); read-threads push through ONE guard that checks a `_window_open`
  flag + try/except so a torn-down window can never crash them. On close: terminate+close each PTY then
  `taskkill /F /T` its pid (ConPTY has no signal tree, so claude/node grandchildren would orphan).
- **Glass:** WebView2 **cannot** be transparent on Windows, so the glass is self-contained - an in-app
  gradient + translucent `backdrop-filter` panels - identical on Win10/11 (no OS acrylic dependency).
- **Launch + deps:** `bin\sonelle_gui.ps1` bootstraps a local `.venv` (`pywebview` + `pywinpty`, pinned in
  `app\requirements.txt`) on first run, then starts the GUI with `pythonw` (no console). The window
  passes `icon=assets\icon\sonelle.ico` to `webview.start()`, so the taskbar shows the sonelle mark, not
  `pythonw.exe`'s Python feather (pywebview falls back to the exe's icon otherwise). `xterm.js` +
  `addon-fit` are vendored under `app\ui\vendor\` (MIT, offline). selftest section 8e checks the files,
  the JS<->Python contract markers, the launcher wiring, and `py_compile`s the backend; section 1 excludes `.venv`.

## Billing
The terminal hands prompts to `claude` (Claude Code), which runs on your Claude Pro/Max
subscription — no API key for personal use. (Shipping this as a product to *other* users
would require API-key auth; personal use does not.)

## House rules
- PowerShell scripts are **pure ASCII** (PS 5.1 misreads non-ASCII in a no-BOM `.ps1`).
  Build glyphs at runtime via `[char]` codepoints.
- Registry rows have a fixed column shape — `new_project.ps1` writes them; don't hand-edit.
