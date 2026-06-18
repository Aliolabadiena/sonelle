# luna

A reusable **engine** for running many projects through one orchestrator (Claude):
zero-hallucination onboarding, project **healing**, and **self-improvement from memory**.

> luna is the ENGINE, not your data. Projects you create with luna are separate from
> luna and never live in this repo. This repo contains **no personal information**.

## Quick start
1. Clone this repo (any machine).
2. *(optional)* copy `luna.config.example.json` -> `luna.config.json` and set `hub` to
   your workspace path (where `CLAUDE.md` + `PROJECTS.md` + `memory/` live). Default `.`
   = this folder. `luna.config.json` is gitignored, so your local paths never enter the repo.
3. Log into your Claude subscription (Claude Code / `claude`).
4. Run the terminal:  `powershell -File bin\luna.ps1`
5. Create a project:  type `:new`  (or `tools\new_project.ps1 <short> "<name>" "<path>"`)
6. Work:  type `myproj: do the thing`

## The three superpowers
- **Scaffold** — new projects in one command, consistently structured (`tools\new_project.ps1`).
- **Heal** — detect & fix project errors: `tools\doctor.ps1` finds problems, Claude diagnoses
  and fixes in a loop until green (see `docs\HEAL.md`).
- **Self-improve** — after every task, lessons/gotchas/feedback are written to `memory/`;
  the next session recalls them before starting (see `docs\SELF_IMPROVE.md`).

## Runs on your Claude subscription
The terminal hands prompts to `claude` (Claude Code), which runs on your Pro/Max plan —
**no API key needed for personal use.**

## What's inside
| Path | What |
|---|---|
| `bin\luna.ps1` | the terminal (Claude-styled launcher; routes to `claude`) |
| `CLAUDE.md` | the dispatcher — how a session orients + routes |
| `PROJECTS.md` | the registry (single source of truth; starts empty) |
| `tools\new_project.ps1` | scaffold a new project (full skeleton + registry row) |
| `tools\check_pointers.ps1` | validate every registry pointer resolves |
| `tools\doctor.ps1` | health check / heal detector for a project |
| `tools\log_lesson.ps1` | capture a lesson into memory (self-improve) |
| `templates\` | project skeletons used by `new_project` |
| `docs\` | `HEAL.md`, `SELF_IMPROVE.md`, `ARCHITECTURE.md` |

## Notes
- PowerShell scripts are **pure ASCII on purpose** (Windows PowerShell 5.1 misreads
  non-ASCII in a no-BOM `.ps1` and breaks parsing). Keep them ASCII.
- Your projects, memory, and state live in your own hub — **separate from this engine.**
