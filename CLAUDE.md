# sonelle — workspace dispatcher (READ FIRST, every session)

sonelle is a reusable engine for running many projects through one orchestrator with
zero-hallucination onboarding. This file is pure POINTERS — live state lives in the
files it points to, refreshed after every task. Never guess state from memory; read
the sources first.

## Grammar
`[address,] <shortcode>: <prompt>`  — e.g. `sonelle, myproj: fix the build`
(You may address the assistant by name; it still replies starting with your canary if you set one.)
You type this straight into **Claude Code** (desktop app or the `claude` CLI) opened in the hub folder.
There is no launcher in between: the dispatch below *is* the routing, done by the session itself.

## Dispatch — do this on every message
1. Extract `<shortcode>`. Open **`PROJECTS.md`** (the canonical registry) and find its row.
2. **FOUND** -> read that row's state sources FIRST (TODO + ledger + memory), confirm the
   current state in ONE line (e.g. `[myproj | build green | ledger: feature X done]`), then
   work by the project's rules. Never guess from memory.
3. **NOT FOUND** -> do NOT start work. Ask: "Shortcode `<x>` isn't in the registry. Create a
   new project `<x>`? (or fix the typo)". On confirm -> run
   `tools\new_project.ps1 <x> "<name>" "<path>"` (full skeleton + registry row), then orient as (2).
4. No shortcode / unclear which project -> ask, don't guess.

## The three superpowers
- **SCAFFOLD** — `tools\new_project.ps1 <short> "<name>" "<path>"` creates a project with the
  full skeleton (TODO + ledger + project CLAUDE.md + memory file + registry row).
- **HEAL** — `tools\doctor.ps1 [<short>]` detects problems (broken pointers, dirty git, failing
  project checks, *unconfigured* placeholder checks, and orphaned state with no registry row). New
  projects ship a real auto-detecting `sonelle.check.ps1` (npm/pytest/dotnet/cargo/go), so "HEALTHY"
  means something was actually checked. To *heal*: run doctor -> diagnose each failure -> fix -> re-run
  until green. Full routine: `docs\HEAL.md`.
- **SELF-IMPROVE** — after EVERY task, reflect and write what was learned (gotchas, user feedback,
  fixes, dead-ends) into `memory/`. Recall is mechanism, not just hope: the **SessionStart hook
  surfaces the memory index into context** before you start. Quick capture: `tools\log_lesson.ps1`.
  Full loop: `docs\SELF_IMPROVE.md`.

## Operating policy (altitude — applies to every session)
You decide WHICH of these workflows to use and WHEN: the goal gets stated, not the tool, so act on your
own judgment instead of waiting to be told "run this". Match effort to the task — on a large or multi-file
change, delegate the breadth-first exploration to subagents and keep your own context for the synthesis
and the edit; on a small focused change just do it. After any code change **verify it yourself** before
calling it done, by running the right check (the engine `selftest`, or the project's `sonelle.check.ps1`) —
unasked; if it fails, **heal** it: root cause, fix, re-run until green. Finish a real task with the
end-of-task ritual below. Scale the ceremony to the task: never over-process a one-liner or a plain
question. The `/selftest`, `/heal`, `/ship` and `/ritual` slash commands bundle these as single steps.

## Enforcement (hooks)
Per project: `.claude/settings.json` wires a **SessionStart** hook (recall reminder), a **Stop** hook
(auto-runs the project's `sonelle.check.ps1` + a capture reminder) and a **PreToolUse guard**, so the
heal/self-improve loop runs via the harness, not just goodwill. Ships in the engine and is scaffolded into
every new project by `new_project.ps1`.

Per hub (v1.47, opt in with `tools\install_hub.ps1 -Hub <hub>`): five more hooks that make the house rules
unbypassable - **HOLD** ("palauk/sustok/stop" opening a message = a full stop for every tool until a
release word), **DELEGATE / MINI / QUESTION** mode (in DELEGATE the main agent briefs a subagent instead of
editing code itself - by hand or through a shell; state files, briefs and docs stay exempt), **model
tiering** (subagents run opus; a Fable subagent needs "fable ok"), **review-only** `reviewer`/`verifier`
subagents, and a Stop check that the turn ends with text for you (+ an optional canary) and that memory
gets pruned on a cadence. Every guard fails OPEN. Detail: `docs\ENFORCEMENT.md`, `docs\AGENTS.md`,
`docs\PRUNE.md`.

## End-of-task ritual (mandatory, every task)
1. Update the project's **TODO** ([x] + short note) and **ledger** (what was done, new gotchas,
   and exact RESUME instructions if unfinished).
2. **SELF-IMPROVE**: capture any lesson / gotcha / feedback into `memory/` (`log_lesson.ps1`).
3. **Validate**: `tools\check_pointers.ps1` — every registry pointer must still resolve.
   Monthly (the Stop hook nudges): `/prune` — archive stale memory + ledger sections.
4. If you keep an off-engine brain backup, sync/commit it (that's your data, not sonelle).
Never leave knowledge only in chat — chat vanishes, files remain.

## How you run it
Open **Claude Code** in the hub (or straight in a project's folder) and type the grammar above. That is
the whole interface — routing, models, effort, permission modes, parallelism and the statusline are all
Claude Code's own. Verify the engine anytime with `tools\selftest.ps1` (or `sonelle.check.ps1`).

## Improving sonelle itself
To work ON the engine (not on a project), open Claude Code **in the engine folder**; `docs\DEVELOPING.md`
seeds that session with the engine-dev invariants (pure-ASCII PowerShell, `tools\selftest.ps1` green
before every commit, no personal data in this public repo) and overrides the dispatcher framing above.
Addressing the engine by its OWN name (`<engine-name>: <prompt>`) means self-development too — never a
project, and never a registry lookup. Everything is git-versioned, so changes are rewindable.

## Engine vs hub
Engine assets (`tools/ templates/ docs/`) are read relative to the scripts. The hub
(`CLAUDE.md` + `PROJECTS.md` + `memory/` + per-project state) is where work lands — default
the engine folder, or any `-Hub <path>` / `sonelle.config.json`. `new_project.ps1` reads
templates from the engine and writes state to the hub, so one engine can drive many hubs.

## House rule
PowerShell scripts here are **pure ASCII** (PS 5.1 misreads non-ASCII in a no-BOM `.ps1`).
Build any box-drawing/arrows at runtime via `[char]` codepoints; keep source ASCII.
