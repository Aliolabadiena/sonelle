# Changelog

## v1.16 — 2026-06-18 (glass app: one input - the terminal itself)
- Removed the bottom composer box (and its placeholder). Two input surfaces (a composer + the
  terminal) was confusing; claude's interactive TUI needs raw keys (arrows, Ctrl+C) in the terminal
  anyway, so the terminal is now the SINGLE input - type `sotis: fix the build` right at the `>`
  prompt, exactly like a normal terminal / Claude Code. The active terminal auto-focuses on open.
- The window is now just the title bar + the terminal pane: nothing else to parse.
- Verified live (real window: no composer, terminal focused, stderr clean); selftest ALL PASS.

## v1.15 — 2026-06-18 (glass app: chat feel, not coding feel)
- The glass app now feels like talking, not coding. `bin\sonelle.ps1` got a `-Bare` switch (no
  welcome card, minimal routing echo - just `> <project>`); the app spawns `sonelle.ps1 -Bare`, so a
  tab opens to a calm empty terminal instead of the welcome/help wall.
- Removed the project chips row from the app. You pick a project the way the grammar already works -
  type `sotis: fix the build` in the one bottom composer - and that's it.
- Composer placeholder is conversational ("ask a project to do something   e.g. sotis: fix the build");
  the empty-state card is trimmed to just an "open a terminal" button.
- selftest: asserts `-Bare` suppresses the welcome and that the backend spawns `sonelle.ps1 -Bare`.
  Verified live (real window: no welcome wall, no chips, clean prompt, stderr clean).
- (The bare welcome only affects the app; a plain `sonelle.ps1` console still shows the full welcome.)

## v1.14 — 2026-06-18 (the liquid-glass desktop app: Python front-end, terminal behind the scenes)
- New `app/`: a frameless Python (pywebview / WebView2) desktop app with a muted dark-purple
  liquid-glass UI. Each tab is an xterm.js terminal; the real PowerShell (`bin\sonelle.ps1`) runs
  BEHIND THE SCENES inside a pseudo-terminal (pywinpty) and is rendered by xterm.js - so what you
  type goes to a hidden shell and the interactive `claude` TUI works in-app. The PowerShell routing
  brain is reused unchanged; the Python layer is purely front-end + PTY plumbing.
- `bin\sonelle_gui.ps1`: bootstraps a local `.venv` (pywebview + pywinpty) on first run, then launches
  the GUI with `pythonw` (no console). `:app` and the taskbar shortcut now open this glass app by
  default; the classic WinForms host stays available via `:app-classic` and `make_launcher -Classic`
  (`-Terminal` still makes a single bare console).
- xterm.js 5.5.0 + @xterm/addon-fit 0.10.0 vendored under `app\ui\vendor\` (MIT, offline). The glass
  is self-contained (in-app gradient + `backdrop-filter` panels) because WebView2 can't be transparent
  on Windows - identical on Win10/11. Needs the Evergreen WebView2 runtime (present on Win10/11).
- selftest section 8e asserts the app files exist, the JS<->Python contract markers are present, the
  launcher wiring is correct, and `py_compile`s the backend; section 1 now excludes `.venv` from the
  ASCII gate. `.gitignore` ignores `.venv/` + `__pycache__/`.
- Engineered from a 4-agent research spec (exact pywebview/pywinpty/xterm integration) and hardened by
  a multi-agent adversarial review. Verified headlessly: backend PTY streams `sonelle.ps1` end-to-end,
  the UI renders (browser preview), and a live pywebview window opens/renders/closes cleanly.

## v1.13 — 2026-06-18 (terminal UI: a calm welcome, Claude Code-style)
- The terminal no longer dumps all 11 commands on every launch. A new `Welcome` function draws a
  single clean rounded card (brand + tagline, your projects pulled live from `PROJECTS.md`, and one
  worked example like `sotis: fix the build`) plus a one-line footer (`runs on your Claude
  subscription  ·  @path attaches an image  ·  :help`). The full command list moved to `:help`
  (on demand) - so the first thing you see is calm and obvious, not a wall.
- The prompt is now just a clay `>` arrow (`  >`), matching the minimal Claude Code feel; routing
  feedback is tidier (`> sotis  opus . xhigh` / code path / prompt on their own dim lines).
- Commands are UNCHANGED - still the `:` prefix (`:help :new :dev` ...) and the same grammar
  `[address,] <short>: <prompt>`. Only the presentation changed; nothing to relearn.
- `:help` and `:projects` got a scannable header + aligned two-column layout. The box-drawing glyphs
  are built at runtime via `[char]` codepoints (source stays pure ASCII); output encoding is set to
  UTF-8 so they render in the embedded app consoles too.
- App (`bin\sonelle_app.ps1`): friendlier empty state ("each tab is a full sonelle"). Each embedded
  tab now shows the new welcome, so the whole app reads cleaner with no structural change.
- selftest section 8b: runs `sonelle.ps1 -Demo`, asserts it exits 0, shows the brand + tagline, no
  longer dumps the command list, has a `Welcome` function drawn with runtime box glyphs, and that
  `:help` still lists every command. ALL PASS.

## v1.12 — 2026-06-18 (the sonelle app: many terminals, one window)
- New `bin\sonelle_app.ps1`: a single Claude-styled window that hosts MANY sonelle terminals as
  tabs. Each tab embeds a REAL console running `bin\sonelle.ps1` (reparented into the window via
  Win32 `SetParent`), so every tab is the exact same terminal you get from `sonelle.ps1` - just
  several at once. `[ + new ]` opens a tab; click a tab to switch; the tab's `[x]` closes it
  (kills that terminal's process tree). Self-contained WinForms host - NO Windows Terminal needed.
- Consoles attach ASYNCHRONOUSLY: a `Forms.Timer` polls each spawned terminal for its window handle
  and then reparents it. No blocking, no `DoEvents` re-entrancy - which is what stops the window from
  crashing when you close a tab or click during attach. Every event handler is wrapped (try/catch +
  runtime `$ErrorActionPreference='Continue'`) so a stray error can never tear the window down. The
  app tracks ONLY the PIDs it spawns and kills exactly those on close (never other terminals).
- Polish: dark native title bar (DWM immersive dark mode), a clay accent line under the tab strip,
  per-tab hover + a clay underline on the active tab, hover states on `+ new` and the close mark.
- New terminal command `:app` launches it (via `Start-Process powershell -Sta`); `:help` lists it.
- `bin\make_launcher.ps1` now makes the primary `sonelle` shortcut open the APP by default (icon,
  launched under `-Sta`); use `-Terminal` for a single bare console shortcut.
- selftest section 5c builds the UI + Win32 interop headlessly (`sonelle_app.ps1 -SelfTest`, which
  shows no window and spawns no terminal) and asserts the embed path, theme, and `:app`/launcher wiring.
- Engineering note: built on WinForms (not WPF) - every control has a native HWND, so hosting a
  real console is robust; WPF would need a fragile `WindowsFormsHost` bridge for the same result.

## v1.11 — 2026-06-18 (config: memoryDir; cleaner validate)
- `check_pointers` + `doctor` are now config-aware: they read `hub` AND a new `memoryDir` from
  `sonelle.config.json` (params still override) via a shared `Get-SonelleConfig` in `tools\_registry.ps1`.
  Set `memoryDir` when your project memory lives OUTSIDE `<hub>\memory` (e.g. a Claude Code memory dir),
  so the validate ritual resolves memory pointers correctly instead of reporting false MISS.
- Precedence: an explicit `-Hub` override uses `<hub>\memory` (config.memoryDir does NOT leak into a
  different / temp hub - e.g. selftest's throwaway hub stays correct). `doctor` forwards `-MemoryDir` to
  `check_pointers`. selftest section 9 covers the resolver precedence.
- (brain-backup, separate `sonelle-state` repo) `sonelle_sync.ps1`: `git add` stderr is now redirected
  like commit/push, so the LF->CRLF warnings no longer surface as error records and the script returns a
  clean exit 0 on success.

## v1.10 — 2026-06-18 (address the engine by its own name)
- The engine's own shortcode now routes to self-development: `<engine-name>: <prompt>` (e.g.
  `sonelle, sonelle: add a :foo command`) is the grammar form of `:dev`. The shortcode is derived from
  the engine folder name (`$script:selfShort`), so it follows a rename. It does NOT touch the registry
  (the engine is still not a project) - `Route` special-cases it to `DevSelf` (carrying staged/inline images).
- `:projects` now lists the reserved self-dev shortcode; `:dev` also forwards staged images.
- selftest section 8 asserts the self-shortcode is derived from the folder name and that `Route` routes it to dev.

## v1.9 — 2026-06-18 (self-development: improve the engine from the engine)
- New terminal command `:dev [prompt]`: opens an orchestrator session (your max model) rooted in the
  engine, seeded so it develops the ENGINE itself - it reads `docs\DEVELOPING.md` + `docs\ARCHITECTURE.md`,
  honors the invariants (pure-ASCII PS, no personal data, no hub state in the engine), and must keep
  `tools\selftest.ps1` green. The seed overrides the dispatcher framing of the root `CLAUDE.md` for that session.
- `docs\DEVELOPING.md`: the canonical guide for changing the engine safely (invariants, the selftest gate,
  "extend selftest for every new feature", rewind-via-git, how to add a command/tool/template).
- `CLAUDE.md` + `docs\ARCHITECTURE.md` + `README.md` updated to point at the self-develop path.
- selftest section 8 asserts the `:dev` handler, the `DevSelf` function, `DEVELOPING.md`, and the
  dispatcher pointer are all wired.

## v1.8 — 2026-06-18 (named "sonelle" + final icon)
- NAME: the engine and its private brain-backup were renamed from the working name `luna` to
  **sonelle** (feminine, distinctive). All folders, file names, file content, the two GitHub repos,
  the user `statusLine` path, the launcher shortcut, and the hub dispatcher refs were updated; old
  GitHub URLs redirect.
- ICON: final mark = a coral sound-wave on a deep-plum rounded tile (`#FF9B85` on `#241A33`),
  superseding the earlier moon-phases concept. `assets/icon/make_icon.py` redraws it ->
  `sonelle.ico` (16-256) + `sonelle.png`; vector source `sonelle.svg`.
- selftest ALL PASS after the rename.

## v1.7 — 2026-06-18 (usage status line)
- `tools/statusline.ps1`: a Claude Code statusLine showing usage every session - `model+effort | 5h% |
  7d% | ctx%`, colour-coded green/amber/red by load. Wire via settings.json `statusLine` ->
  `powershell -NoProfile -File .../tools/statusline.ps1` (+ `refreshInterval`). 5h/7d rate-limit % appear
  for Pro/Max after the first API response; gracefully omitted otherwise (ctx always shown).
- selftest asserts the status line renders usage from a sample payload.
- On-demand subscription audit: the `/usage` slash command (account-level, day/week toggle).

## v1.6 — 2026-06-18 (permissions: no-ask deploy + autonomous lanes)
- Lanes take a permission mode: `sonelle_team` start scripts add `--permission-mode <mode>` (config
  `models.lanePermissionMode`, engine default `acceptEdits`). Set `bypassPermissions` in sonelle.config.json
  for fully-autonomous workers (never prompt).
- Orchestrator optional `models.orchestratorPermissionMode` (default unset -> inherits your global default).
- (User-side, not in repo) allow-rules in `~/.claude/settings.json`: `Bash(ssh *)` / `Bash(scp *)` /
  `Bash(git push*)` so VPS deploy + push never prompt; `skipDangerousModePermissionPrompt` so bypass mode
  isn't gated by the danger dialog.
- MCP NOTE: Supabase/Canva/Drive/Calendar/Gmail are claude.ai ACCOUNT connectors (not project-scoped),
  so every sonelle session inherits them already - nothing to move. Chrome = a browser extension that
  attaches per-session (a sonelle session is attachable).
- selftest asserts lane start scripts carry `--permission-mode`.

## v1.5 — 2026-06-18 (model + effort policy)
- ORCHESTRATOR is ALWAYS max: the terminal session you talk to launches `claude` with
  `--model opus --effort xhigh` (a strong boss orchestrates the workers well). Overridable via
  `sonelle.config.json` `models.orchestrator` / `orchestratorEffort`, but defaults to max.
- LANES (workers) take per-lane model + effort: `:team proj bugs=opus,triage=haiku:medium,write=opus`.
  Each lane's start script runs `claude --model <m> --effort <e>`. Defaults `laneDefault=opus` /
  `laneEffort=high` (config `models.laneDefault` / `laneEffort`); per-lane `name=model[:effort]` overrides.
  Models: `haiku | sonnet | opus | claude-fable-5`; effort `low|medium|high|xhigh` (bad effort rejected).
- The terminal echoes the orchestrator model+effort before each hand-off; selftest asserts the per-lane
  model lands in the start script.

## v1.4 — 2026-06-18 (icon + launcher + multi-instance)
- ICON (initial concept; the final mark is the sonelle coral wave - see v1.8): vector source
  `assets/icon/sonelle.svg` + Pillow generator `assets/icon/make_icon.py` -> multi-size `sonelle.ico`
  (16-256) + `sonelle.png`. Re-themeable (edit colors, re-run).
- LAUNCHER: `bin/make_launcher.ps1` creates a pinnable `sonelle.lnk` (Desktop + Start Menu) carrying the
  icon, opening the sonelle terminal from ANYWHERE. Target = Windows Terminal if installed, else powershell.exe.
- MULTI-INSTANCE: `bin/sonelle_team.ps1` runs up to 5 parallel "lanes" on one project - each a `claude`
  session scoped to a DISJOINT workstream, coordinating via a shared board `<code>/.sonelle/lanes/` +
  disjoint ownership (NOT shared live memory). WT tabs if `wt`, else separate windows. Added `:team
  <proj> <lanes>` and `:status <proj>` to the terminal. Cap 5; warns at >3 (rate limits); rejects
  duplicate/bad lane names; `-DryRun` writes the board + start scripts without launching.
- selftest now covers the new scripts (parse/ASCII) + a sonelle_team dry-run (board + start script + parse).
- NOTE: launcher + lane launching fire in real sessions (structurally verified here). `wt` is not
  installed on this machine -> they use PowerShell windows; install Windows Terminal for tabs.

## v1.3 — 2026-06-18 (enforcement hooks)
- **Heal + self-improve are now ENFORCED, not just ritual.** Added Claude Code hooks in
  `.claude/settings.json`: a **SessionStart** hook (recall reminder -> context) and a **Stop** hook
  (auto-runs the project's `sonelle.check.ps1` + a "capture a lesson" reminder). Hooks ship in the engine
  and are scaffolded into every new project (`.claude/hooks/{session_start,stop}.ps1` + `settings.json`).
- `new_project` now also writes a starter `sonelle.check.ps1` into each project (so the Stop hook + doctor
  have a real health surface to run).
- selftest verifies hook scripts parse + are ASCII, both `settings.json` files are valid JSON, and a
  scaffolded project gets `.claude/settings.json` + hooks + `sonelle.check.ps1`.
- NOTE: hooks are structurally verified (parse / JSON / scaffold) but fire only inside real Claude Code
  sessions - not triggered in this build session. Conservative by design (always exit 0, Test-Path guards).

## v1.2 — 2026-06-18 (skeptical-audit fixes)
- **SECURITY:** `.gitignore` had trailing inline comments (git treats `pattern  # x` as a literal
  filename), so `sonelle.config.json` / `memory/` / `*_TODO.txt` were NOT ignored - a `git add -A`
  could have leaked a hub's brain to the public repo. Comments moved to their own lines; verified
  via `git check-ignore` (now a selftest gate).
- **check_pointers** silently validated ZERO projects: its `([^\r\n]*)$` row regex didn't match the
  CRLF rows `new_project` wrote. Root cause was 4 divergent registry regexes; replaced with ONE
  shared CRLF-safe parser `tools\_registry.ps1` used by check_pointers, doctor, and the terminal.
- **selftest** now proves the validator actually works: asserts check_pointers flips to exit 1 on a
  deleted code path, and asserts `.gitignore` ignores the private paths. Both critical bugs would now fail the test.
- `log_lesson.ps1` gained `-Hub` (was writing memory into the engine, not the hub).
- `new_project` normalizes line endings (LF) so it never writes mixed CRLF/LF again.
- Terminal: safe address-strip (only strips a leading `addr,` before a real `short:`; no more
  mangling prose with commas); `@path` only stripped when it's a real file (emails/@handles/decorators
  survive); echoes the final prompt before handing to `claude`; lowercases the shortcode; enables VT /
  falls back to no-color (respects `NO_COLOR`).
- `doctor`: guards missing `git`/`PROJECTS.md`, adds an environment preflight (PowerShell + `claude`
  on PATH), and distinguishes HEALTHY from NOTHING-CHECKED (empty registry no longer reads green).
- Docs made honest: "any machine" -> "any Windows machine + prereqs"; HEAL = detect + manual fix;
  SELF-IMPROVE = capture + discipline (not engine-enforced); documented CLAUDE.md auto-load behavior.

## v1.1 — 2026-06-18
- `-Hub` threading across `new_project` / `check_pointers` / `doctor` + the terminal, so one
  engine can drive a separate workspace coherently.
- Engine vs hub separation: templates are read from the engine, state is written to the hub
  (fixes scaffolding into an external `-Hub`).
- Terminal: image attach via `:attach <path>` and inline `@<path>`; `:clear`.
- `tools\selftest.ps1` + `sonelle.check.ps1`: end-to-end self-test (parse/ASCII/scaffold/
  check_pointers/doctor/duplicate-guard) into a throwaway temp hub. All pass.
- Fixed `$args` automatic-variable shadowing in the terminal's heal path.

## v1.0 — 2026-06-18
- Dispatcher (`CLAUDE.md`) + registry (`PROJECTS.md`) + grammar `[address,] <short>: <prompt>`.
- Claude-styled terminal `bin\sonelle.ps1` (routes to `claude`, runs on a Claude subscription).
- Three superpowers: scaffold (`new_project`), heal (`doctor` + `docs\HEAL.md`),
  self-improve (`log_lesson` + `docs\SELF_IMPROVE.md`).
- Templates, docs (`HEAL`, `SELF_IMPROVE`, `ARCHITECTURE`). Pure-ASCII PowerShell.
