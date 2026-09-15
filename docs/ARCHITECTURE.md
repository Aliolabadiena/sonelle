# ARCHITECTURE — how sonelle fits together

## Engine vs your data
- **sonelle (this repo) = the ENGINE.** Reusable mechanism: dispatcher, registry format,
  templates, scaffold/heal/improve tools, hooks, skills. **No personal data.**
- **Your projects = separate.** Created *using* sonelle, but they are not sonelle. Their code,
  state (TODO/ledger), and memory live in your own hub, never in this repo.

A fresh clone on any machine + your Claude login = a working, empty workspace you can
create new projects in.

## The flow
```
you ── "myproj: do X" ──> your Claude Code session (opened in the hub)
                             │  reads CLAUDE.md (dispatcher) + PROJECTS.md (registry, single source of truth)
                             ├─ found ──> read that row's state ──> work in <code path>
                             └─ not found ──> ask, then new_project.ps1 ──> registry row
```
There is no launcher process: the dispatch is a convention the session follows, and every step of it is
a file it can read or a tool it can run.
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
arbitrary engine path. That is what decides which dispatcher governs a session:
- Open Claude Code in the **hub** -> it loads the hub's `CLAUDE.md` (this engine's dispatcher template),
  so the grammar + registry routing above apply, and the session works in a project's code path from there.
- Open it directly in a **project's** folder -> it loads that project's `CLAUDE.md` (the per-project
  pointer carrying read-state-first + the end-of-task ritual) and no routing is needed.
- Open it in the **engine** folder -> you are developing the engine: `docs\DEVELOPING.md` is the authority
  for that session and overrides the dispatcher framing of the root `CLAUDE.md`. Addressing the engine by
  its own name (`<engine-name>: <prompt>`) means the same thing - never a registry lookup.

A hub with its OWN `CLAUDE.md` governs its own sessions; sonelle's tools only read `PROJECTS.md` and never
merge hub-level dispatchers.

## Parallelism
sonelle ships no lane launcher. Run several workstreams with Claude Code's own subagent / workflow tools
inside one session, or open multiple sessions on **git worktrees** with DISJOINT file ownership (that
disjointness is the load-bearing part, especially on a project without git merge safety). Note the cost:
N concurrent sessions burn roughly Nx the subscription usage.

## Autonomy + guard hooks
- **Permission modes** are Claude Code's own (`default` / `acceptEdits` / `plan` / `bypassPermissions`,
  etc.) - set them in the session rather than through sonelle.
- **The operating policy** (proactively pick the workflow, delegate breadth-first exploration to subagents
  on multi-file work, verify with the right check unasked, heal on failure, run the end-of-task ritual,
  and scale the ceremony down on a one-liner) lives in the dispatcher `CLAUDE.md` plus the hooks and the
  skills below - it is read from files every session, not injected by a launcher.
- **PreToolUse guard + slash commands:** because an autonomous permission mode removes claude's own
  prompts, the engine and every scaffolded project ship a **PreToolUse guard hook**
  (`.claude\hooks\pretooluse_guard.ps1`, wired in `.claude\settings.json`) - claude runs it BEFORE every
  `Write`/`Edit`/`Bash` and it EXITS 2 to block the call (feeding the reason back to claude) or 0 to allow,
  failing open on any error so it can never break a session. The engine guard enforces the house rule
  (pure-ASCII `.ps1`) and invariant #4 (no hub state / `new_project` / plain `log_lesson` at the engine
  root) and blocks force-push; the project guard blocks force-push and is yours to extend. **Slash
  commands** (`.claude\commands\`: `/selftest /heal /ship /ritual`) turn the rituals into one keystroke.
  selftest 8h covers the guard behaviorally (block/allow) plus the wiring and the commands.
- **Skills** (`.claude\skills\` + `templates\skills\`) are the other half of the policy: claude auto-loads
  `systematic-debugging` / `verification-before-completion` / `plan-before-build` (engine + every project)
  and the web trio (`frontend-design` / `design-review` / `accessibility-audit`) by task, so the discipline
  arrives with the work instead of being remembered.
- **Bringing an existing codebase in:** point `new_project.ps1` at it, or ask the session to adapt the
  generic scaffold to the real code. Back up any existing `CLAUDE.md` / `.claude\` first.

## Billing
You work in Claude Code, which runs on your Claude Pro/Max subscription — no API key for personal
use. sonelle itself adds no billing path. (Shipping this as a product to *other* users would require
API-key auth; personal use does not.)

## House rules
- PowerShell scripts are **pure ASCII** (PS 5.1 misreads non-ASCII in a no-BOM `.ps1`).
  Build glyphs at runtime via `[char]` codepoints.
- Registry rows have a fixed column shape — `new_project.ps1` writes them; don't hand-edit.
