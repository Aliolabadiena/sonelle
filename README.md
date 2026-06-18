# sonelle

A reusable **engine** for running many projects through one orchestrator (Claude):
zero-hallucination onboarding, project **healing**, and **self-improvement from memory**.

> sonelle is the ENGINE, not your data. Projects you create with sonelle are separate from
> sonelle and never live in this repo. This repo contains **no personal information**.

## Quick start
1. Clone this repo. **Prereqs:** Windows + PowerShell 5.1+, the `claude` CLI installed and on
   PATH (logged into your Claude subscription), `git`, and a VT-capable terminal (e.g. Windows
   Terminal). macOS/Linux are not supported yet (PowerShell-only).
2. *(optional)* copy `sonelle.config.example.json` -> `sonelle.config.json` and set `hub` to
   your workspace path (where `CLAUDE.md` + `PROJECTS.md` + `memory/` live). Default `.`
   = this folder. `sonelle.config.json` is gitignored, so your local paths never enter the repo.
3. Log into your Claude subscription (Claude Code / `claude`).
4. Run the terminal:  `powershell -File bin\sonelle.ps1`
5. Create a project:  type `:new`  (or `tools\new_project.ps1 <short> "<name>" "<path>"`)
6. Work:  type `myproj: do the thing`
7. Attach an image:  `myproj: what's in @C:\pics\food.jpg?`  (or `:attach <path>` to stage one)
8. Verify the engine:  `powershell -File tools\selftest.ps1`
9. Pin to taskbar:  `powershell -File bin\make_launcher.ps1`, then right-click the Desktop `sonelle` shortcut -> Pin to taskbar.
10. Multi-instance:  `:team myproj bugs=opus,docs=haiku` opens parallel lanes (per-task models); `:status myproj` shows them. The orchestrator (your terminal session) always runs your max model (`opus`/`xhigh`).
11. Improve sonelle itself:  type `:dev` (opens a dev session in the engine, seeded with `docs\DEVELOPING.md`; keep `selftest` green before committing).

## The three capabilities (honest about what's mechanism vs discipline)
- **Scaffold** (real mechanism) — new projects in one command, consistently structured (`tools\new_project.ps1`).
- **Heal** (detector + guided fix) — `tools\doctor.ps1` DETECTS problems; the diagnose->fix->verify
  loop is Claude-driven. A **Stop hook** (`.claude/settings.json`) auto-runs each project's
  `sonelle.check.ps1` after every task. With no `sonelle.check.ps1` it's just "code path exists" (`docs\HEAL.md`).
- **Self-improve** (capture + hook-enforced loop) — `tools\log_lesson.ps1` writes lessons to `memory/`;
  a **SessionStart hook** reminds to recall before, a **Stop hook** reminds to capture after — so the
  loop is enforced by the harness, not just discipline (`docs\SELF_IMPROVE.md`). Hooks ship in
  `.claude/` and are scaffolded into every new project.

## Runs on your Claude subscription
The terminal hands prompts to `claude` (Claude Code), which runs on your Pro/Max plan —
**no API key needed for personal use.**

## What's inside
| Path | What |
|---|---|
| `bin\sonelle.ps1` | the terminal (Claude-styled launcher; routes to `claude`) |
| `CLAUDE.md` | the dispatcher — how a session orients + routes |
| `PROJECTS.md` | the registry (single source of truth; starts empty) |
| `tools\new_project.ps1` | scaffold a new project (full skeleton + registry row) |
| `tools\check_pointers.ps1` | validate every registry pointer resolves |
| `tools\doctor.ps1` | health check / heal detector for a project |
| `tools\log_lesson.ps1` | capture a lesson into memory (self-improve) |
| `tools\selftest.ps1` | end-to-end self-test (dogfoods scaffold/heal into a temp hub) |
| `tools\statusline.ps1` | usage status line: 5h/7d rate-limit %, context % |
| `sonelle.check.ps1` | the engine's own health check (runs the self-test) |
| `bin\make_launcher.ps1` | create a pinnable taskbar shortcut (`sonelle.lnk`) with the icon |
| `bin\sonelle_team.ps1` | run up to 5 parallel lanes on one project (multi-instance) |
| `assets\icon\` | app icon: `sonelle.svg` (vector) + `make_icon.py` -> `sonelle.ico` / `sonelle.png` |
| `templates\` | project skeletons used by `new_project` |
| `docs\` | `HEAL.md`, `SELF_IMPROVE.md`, `ARCHITECTURE.md`, `DEVELOPING.md` (how to improve the engine) |

## Engine vs hub (where things live)
The **engine** assets (this repo: `bin/`, `tools/`, `templates/`, `docs/`) are always read
from where the scripts live. Your **hub** (the `CLAUDE.md` + `PROJECTS.md` + `memory/` +
per-project state) is where work lands — by default the engine folder, or any path you pass
via `-Hub` / `sonelle.config.json`. So you can drive a separate workspace with one engine.
Image attach: stage with `:attach <path>` or inline `@<path>` in a prompt.

## Notes
- PowerShell scripts are **pure ASCII on purpose** (Windows PowerShell 5.1 misreads
  non-ASCII in a no-BOM `.ps1` and breaks parsing). Keep them ASCII.
- Your projects, memory, and state live in your own hub — **separate from this engine.**
