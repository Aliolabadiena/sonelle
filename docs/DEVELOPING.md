# DEVELOPING sonelle (improving the engine itself)

This guide is for working ON the engine (this repo), not for using it to run projects.
Read it whenever you open Claude Code in the sonelle folder.

> The root `CLAUDE.md` is the **dispatcher** (how a session routes PROJECTS). When you are
> developing the engine, THIS file governs the session - not the dispatcher framing.

## Session framing (engine-dev sessions)
Open Claude Code **in the engine folder** - or address the engine by its own name
(`<engine-name>: <prompt>`, e.g. `sonelle, sonelle: add a doctor check`), which means
self-development and never a registry lookup. Claude Code auto-loads the root `CLAUDE.md`
(the dispatcher template the engine ships) into context - but **this file is your sole authority for
the session**. If anything in `CLAUDE.md` talks about routing a shortcode, scaffolding a project,
reading hub state, or an end-of-task ritual, **disregard it**: you are improving the ENGINE, not
running a project through it. The invariants below are absolute and override any dispatcher guidance.

## Operating policy (engine-dev)
Decide the workflow yourself from the task; the goal gets stated, not the tool. Delegate breadth-first
exploration to subagents on a multi-file change and keep your own context for the synthesis and the edit;
do a small focused change directly. VERIFY every change by running `tools\selftest.ps1` before calling it
done, unasked; on red, HEAL to green rather than reporting red. Capture the lesson (below) when you learn
something reusable. Scale the ceremony to the task - a one-line fix gets no process. For a project session
the same policy lives in the dispatcher `CLAUDE.md`; the `/selftest /heal /ship /ritual` slash commands
bundle the routines either way.

## What you are touching
sonelle is the reusable ENGINE: the dispatcher, the registry format, the templates, the
scaffold/heal/self-improve tools, the hooks, and the skills. It is a **public** repo with
**zero personal data**. It is a Claude Code **workflow**, not a launcher - there is no
terminal/REPL to maintain (removed in v1.46).

## Invariants (do NOT break these)
1. **Pure ASCII PowerShell.** PS 5.1 misreads non-ASCII in a no-BOM `.ps1`. Build any glyphs at
   runtime via `[char]` codepoints. selftest fails on any non-ASCII byte in a `.ps1`.
2. **selftest is the gate.** Run `tools\selftest.ps1` and confirm **ALL PASS** before every commit.
   If you add a feature, EXTEND selftest to cover it - the engine must stay self-verifying.
3. **No personal data, ever.** No real hub paths, project names, keys, or memory in this repo.
   `sonelle.config.json`, `memory/`, `*_TODO.txt` are gitignored on purpose - keep it that way.
4. **Do not pollute the engine with hub state.** The engine is not one of your projects. Never
   scaffold TODO / ledger / project-CLAUDE / memory into the engine root.
5. **Registry rows only via `new_project.ps1`** (fixed column shape; never hand-edit rows).
6. **Keep the split:** root `CLAUDE.md` = the dispatcher (and the template a hub adopts);
   `templates\CLAUDE.template.md` = the per-project skeleton. Do not merge these two roles.

## Workflow
1. Read `docs\ARCHITECTURE.md` first (how the pieces fit + the CLAUDE.md load behavior).
2. Make the change. Match the existing style (ASCII; the palette + format-string `Write-Host` calls).
3. `tools\selftest.ps1` -> ALL PASS. Red = fix or revert; never commit red.
4. Commit + push to the public repo. Everything is git-versioned, so **rewind freely** -
   experiment, and `git revert` / `git reset` if a direction turns out wrong.
5. Capture lessons. A **generic, cross-project** lesson (no personal data) ships IN the engine via
   `tools\log_lesson.ps1 -Shared` -> `knowledge\` (public, ASCII, indexed by `knowledge\INDEX.md`); a
   **personal / per-project** lesson goes to YOUR gitignored hub `memory\` (default, no `-Shared`). The
   shared `knowledge\` base is curated engine content (like `docs\`/`templates\`), NOT hub state - so it
   does not violate invariant 4; just keep it personal-data-free. The SessionStart hook recalls both.

## Common changes
- **New tool:** add `tools\<name>.ps1` (ASCII, `$ErrorActionPreference='Stop'`, `-Hub`-aware if it
  touches hub state), wire it where it is used, and cover it in selftest.
- **New template:** add it to `templates\`, have `new_project.ps1` write it, and assert it
  scaffolds in selftest (the golden template set in T2 must be updated deliberately).
- **Dispatcher / policy change:** the routing grammar, the three superpowers, the operating policy and
  the end-of-task ritual all live in the root `CLAUDE.md`; the per-project equivalent is
  `templates\CLAUDE.template.md`. Keep those two roles split (invariant 6).
- **Config:** `Get-SonelleConfig` in `tools\_registry.ps1` is the ONLY parser of `sonelle.config.json`
  (`hub`, `memoryDir`, and a pass-through `Models` block); `$env:SONELLE_CONFIG` repoints the file,
  which is how selftest stays hermetic. A malformed config must warn and fall back, never silently
  relocate the hub. NOTE (v1.46): nothing in the engine applies the `models` block any more - model,
  effort and permission mode are chosen in Claude Code itself.
- **Guard hook + slash commands (v1.36):** the engine and every scaffolded project
  ship a **PreToolUse guard** (`.claude\hooks\pretooluse_guard.ps1`, wired in `.claude\settings.json` for
  `Write|Edit|Bash`). It reads claude's UTF-8 payload on stdin (`OpenStandardInput` as UTF-8 - PS 5.1's
  `[Console]::In` uses the console code page and would corrupt non-ASCII), and on a violation EXITS 2 to
  BLOCK the call (stderr goes back to claude); any parse/read problem EXITS 0 (a guard must never break a
  session). It is the only guardrail left in a `bypassPermissions` session. The ENGINE guard enforces
  the house rule (no non-ASCII written to a `.ps1`) and invariant #4 (no `new_project`, no plain
  `log_lesson` - only `-Shared` -> `knowledge\`; no `*_TODO.txt`/`*_run_STATUS.md`/`memory\` at the engine
  root) plus blocks force-push; the PROJECT template guard blocks force-push and is a stub to add your own
  rules. **Slash commands** (`.claude\commands\`: `/selftest /heal /ship /ritual`) codify the rituals -
  engine versions drive `selftest`/`doctor`/the commit gate, scaffolded versions drive `sonelle.check.ps1`
  + the project's TODO/ledger. Guarded by selftest 8h (guard exists + behavioral block/allow incl. the
  non-ASCII case + commands + wiring).
- **Skills:** `templates\skills\` is the single source of truth; the engine's three discipline skills
  (`.claude\skills\`) must stay byte-identical to their templates, and `plugin\` is regenerated from them
  via `tools\build_plugin.ps1`. selftest 8j + 12 enforce both (no drift).
- **Bringing in an existing codebase:** point `new_project.ps1` at it, then have the session adapt the
  generic scaffold to the real code. Back up any existing `CLAUDE.md` / `sonelle.check.ps1` / `.claude\`
  to `*.pre-sonelle.bak` first - the scaffold must never destroy a project's own onboarding.
- **Docs:** keep `README.md` + `docs\ARCHITECTURE.md` honest (mechanism vs discipline), and add a
  `CHANGELOG.md` entry.

## Releasing
Bump `CHANGELOG.md` (new top entry), keep README's "What's inside" table current, run selftest,
commit, push. There are no version tags yet - the CHANGELOG is the source of truth.
