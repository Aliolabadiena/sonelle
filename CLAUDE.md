# luna — workspace dispatcher (READ FIRST, every session)

luna is a reusable engine for running many projects through one orchestrator with
zero-hallucination onboarding. This file is pure POINTERS — live state lives in the
files it points to, refreshed after every task. Never guess state from memory; read
the sources first.

## Grammar
`[address,] <shortcode>: <prompt>`  — e.g. `luna, myproj: fix the build`
(You may address the assistant by name; it still replies starting with your canary if you set one.)

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
- **HEAL** — `tools\doctor.ps1 [<short>]` detects problems (broken pointers, dirty git,
  failing project checks). To *heal*: run doctor -> diagnose each failure -> fix -> re-run
  until green. Full routine: `docs\HEAL.md`.
- **SELF-IMPROVE** — after EVERY task, reflect and write what was learned (gotchas, user
  feedback, fixes, dead-ends) into `memory/` so the next session recalls it. Recall relevant
  memory BEFORE starting. Quick capture: `tools\log_lesson.ps1`. Full loop: `docs\SELF_IMPROVE.md`.

## End-of-task ritual (mandatory, every task)
1. Update the project's **TODO** ([x] + short note) and **ledger** (what was done, new gotchas,
   and exact RESUME instructions if unfinished).
2. **SELF-IMPROVE**: capture any lesson / gotcha / feedback into `memory/` (`log_lesson.ps1`).
3. **Validate**: `tools\check_pointers.ps1` — every registry pointer must still resolve.
4. If you keep an off-engine brain backup, sync/commit it (that's your data, not luna).
Never leave knowledge only in chat — chat vanishes, files remain.

## The terminal
`bin\luna.ps1` is the luna terminal (Claude-styled). It parses the grammar above, routes to
the right project via `PROJECTS.md`, and hands the prompt to `claude` (your Claude
subscription). `bin\luna.ps1 -Demo` shows the banner without entering the REPL.

## House rule
PowerShell scripts here are **pure ASCII** (PS 5.1 misreads non-ASCII in a no-BOM `.ps1`).
Build any box-drawing/arrows at runtime via `[char]` codepoints; keep source ASCII.
