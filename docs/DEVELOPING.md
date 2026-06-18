# DEVELOPING sonelle (improving the engine itself)

This guide is for working ON the engine (this repo), not for using it to run projects.
Open it via the terminal command `:dev` (which seeds a Claude session here with this context),
or read it before you `cd` into the sonelle folder and run `claude`.

> The root `CLAUDE.md` is the **dispatcher** (how a session routes PROJECTS). When you are
> developing the engine, THIS file governs the session - not the dispatcher framing.

## Session framing (how `:dev` works)
When you run `:dev`, sonelle launches a Claude session in the engine root, seeded with these
instructions. Claude Code ALSO auto-loads the root `CLAUDE.md` (the dispatcher template the engine
ships) into context - but **this file is your sole authority for the session**. If anything in
`CLAUDE.md` talks about routing a shortcode, scaffolding a project, reading hub state, or an
end-of-task ritual, **disregard it**: you are improving the ENGINE, not running a project through it.
The invariants below are absolute and override any dispatcher guidance.

## What you are touching
sonelle is the reusable ENGINE: the dispatcher, the registry format, the templates, the
scaffold/heal/self-improve tools, the terminal, and the lanes. It is a **public** repo with
**zero personal data**.

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
5. Capture any lesson in YOUR memory (not the engine) so the next session recalls it.

## Common changes
- **New terminal command:** add a handler in the REPL loop of `bin\sonelle.ps1`, a line in
  `ShowHelp`, and a selftest assertion that the handler exists.
- **New tool:** add `tools\<name>.ps1` (ASCII, `$ErrorActionPreference='Stop'`, `-Hub`-aware if it
  touches hub state), wire it where it is used, and cover it in selftest.
- **New template:** add it to `templates\`, have `new_project.ps1` write it, and assert it
  scaffolds in selftest.
- **Docs:** keep `README.md` + `docs\ARCHITECTURE.md` honest (mechanism vs discipline), and add a
  `CHANGELOG.md` entry.

## Releasing
Bump `CHANGELOG.md` (new top entry), keep README's "What's inside" table current, run selftest,
commit, push. There are no version tags yet - the CHANGELOG is the source of truth.
