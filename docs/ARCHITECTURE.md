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

## Multi-instance (lanes)
`bin\sonelle_team.ps1 <proj> -Lanes a,b,c` runs up to 5 parallel `claude` sessions on one project, each a
LANE scoped to a disjoint workstream (e.g. bugs / concepts / website). They do NOT share live memory -
they coordinate via a shared board at `<code>\.sonelle\lanes\` (one status file per lane) + DISJOINT file
ownership (critical when the project has no git merge safety). Windows Terminal tabs if `wt` is
installed, else separate PowerShell windows. `:team` / `:status` in the terminal wrap it. Hard cap 5;
>3 warns about rate limits (N lanes ~= Nx subscription usage).

## Billing
The terminal hands prompts to `claude` (Claude Code), which runs on your Claude Pro/Max
subscription — no API key for personal use. (Shipping this as a product to *other* users
would require API-key auth; personal use does not.)

## House rules
- PowerShell scripts are **pure ASCII** (PS 5.1 misreads non-ASCII in a no-BOM `.ps1`).
  Build glyphs at runtime via `[char]` codepoints.
- Registry rows have a fixed column shape — `new_project.ps1` writes them; don't hand-edit.
