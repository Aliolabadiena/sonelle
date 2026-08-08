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

## Autonomy, guard hooks + onboarding (terminal features)
- **Skip permission prompts (yolo):** by default `claude` asks before risky actions. Set `SONELLE_YOLO=1`
  (or launch with `-Yolo`), which runs `claude --permission-mode bypassPermissions`
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
- **Onboarding primer, :adopt, and the general lane (v1.37):** `-Bare` mode
  greets you with a short no-claude primer (how to make a project, adopt an existing one, run a task,
  connect claude) instead of a blank prompt; `help`/`?` shows the commands without ever calling claude.
  **`:adopt <path>`** brings an existing, non-sonelle codebase into the workflow: it scaffolds the skeleton
  over it (backing up any `CLAUDE.md`/`.claude\` to `*.pre-sonelle.bak` first), then asks claude to adapt
  the generic scaffold to the real code - best-effort, and honest that a very different structure may need
  a manual fix. **`general: <prompt>`** is a one-off lane for a quick question or throwaway task: it runs in
  a neutral scratch dir (`%TEMP%\sonelle_general`) with no project, no registry row, and no saved state, so
  it never clutters your real projects' memory or docs.
## Billing
The terminal hands prompts to `claude` (Claude Code), which runs on your Claude Pro/Max
subscription — no API key for personal use. (Shipping this as a product to *other* users
would require API-key auth; personal use does not.)

## House rules
- PowerShell scripts are **pure ASCII** (PS 5.1 misreads non-ASCII in a no-BOM `.ps1`).
  Build glyphs at runtime via `[char]` codepoints.
- Registry rows have a fixed column shape — `new_project.ps1` writes them; don't hand-edit.
