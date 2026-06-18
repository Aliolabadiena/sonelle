# luna

A reusable **engine** for running many projects through one orchestrator (Claude):
zero-hallucination onboarding, project **healing**, and **self-improvement from memory**.

> luna is the ENGINE, not your data. Projects you create with luna are separate from
> luna and never live in this repo. This repo contains **no personal information**.

## Quick start
1. Clone this repo. **Prereqs:** Windows + PowerShell 5.1+, the `claude` CLI installed and on
   PATH (logged into your Claude subscription), `git`, and a VT-capable terminal (e.g. Windows
   Terminal). macOS/Linux are not supported yet (PowerShell-only).
2. *(optional)* copy `luna.config.example.json` -> `luna.config.json` and set `hub` to
   your workspace path (where `CLAUDE.md` + `PROJECTS.md` + `memory/` live). Default `.`
   = this folder. `luna.config.json` is gitignored, so your local paths never enter the repo.
3. Log into your Claude subscription (Claude Code / `claude`).
4. Run the terminal:  `powershell -File bin\luna.ps1`
5. Create a project:  type `:new`  (or `tools\new_project.ps1 <short> "<name>" "<path>"`)
6. Work:  type `myproj: do the thing`
7. Attach an image:  `myproj: what's in @C:\pics\food.jpg?`  (or `:attach <path>` to stage one)
8. Verify the engine:  `powershell -File tools\selftest.ps1`

## The three capabilities (honest about what's mechanism vs discipline)
- **Scaffold** (real mechanism) — new projects in one command, consistently structured (`tools\new_project.ps1`).
- **Heal** (detector + guided fix) — `tools\doctor.ps1` DETECTS problems (broken pointers, a failing
  per-project `luna.check.ps1`); the diagnose->fix->verify loop is Claude-driven, not automatic
  (see `docs\HEAL.md`). With no `luna.check.ps1`, a project's health check is just "code path exists".
- **Self-improve** (capture tool + discipline) — `tools\log_lesson.ps1` writes lessons to `memory/`;
  recall-before / reflect-after is a ritual a session follows, **not enforced by the engine** yet
  (see `docs\SELF_IMPROVE.md`).

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
| `tools\selftest.ps1` | end-to-end self-test (dogfoods scaffold/heal into a temp hub) |
| `luna.check.ps1` | the engine's own health check (runs the self-test) |
| `templates\` | project skeletons used by `new_project` |
| `docs\` | `HEAL.md`, `SELF_IMPROVE.md`, `ARCHITECTURE.md` |

## Engine vs hub (where things live)
The **engine** assets (this repo: `bin/`, `tools/`, `templates/`, `docs/`) are always read
from where the scripts live. Your **hub** (the `CLAUDE.md` + `PROJECTS.md` + `memory/` +
per-project state) is where work lands — by default the engine folder, or any path you pass
via `-Hub` / `luna.config.json`. So you can drive a separate workspace with one engine.
Image attach: stage with `:attach <path>` or inline `@<path>` in a prompt.

## Notes
- PowerShell scripts are **pure ASCII on purpose** (Windows PowerShell 5.1 misreads
  non-ASCII in a no-BOM `.ps1` and breaks parsing). Keep them ASCII.
- Your projects, memory, and state live in your own hub — **separate from this engine.**
