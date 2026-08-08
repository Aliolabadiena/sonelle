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
   = this folder. If your project memory lives OUTSIDE `<hub>/memory` (e.g. a Claude Code memory
   dir), set `memoryDir` to that path so heal/validate resolve memory pointers correctly.
   `sonelle.config.json` is gitignored, so your local paths never enter the repo.
3. Log into your Claude subscription (Claude Code / `claude`).
4. Run the terminal:  `powershell -File bin\sonelle.ps1`  (a clean welcome card shows your projects; type `:help` for the full command list)
5. Create a project:  type `:new`  (or `tools\new_project.ps1 <short> "<name>" "<path>"`)
6. Work:  type `myproj: do the thing`
7. Attach an image:  `myproj: what's in @C:\pics\food.jpg?`  (or `:attach <path>` to stage one)
8. Verify the engine:  `powershell -File tools\selftest.ps1`
9. Pin to taskbar:  `powershell -File bin\make_launcher.ps1` (the `sonelle` shortcut opens the terminal - Windows Terminal if installed), then right-click the Desktop `sonelle` shortcut -> Pin to taskbar.
10. Multi-instance:  `:team myproj bugs=opus,docs=haiku` opens parallel lanes (per-task models); `:status myproj` shows them. The orchestrator (your terminal session) always runs your max model (`opus`/`xhigh`).
11. Improve sonelle itself:  type `:dev` (or address the engine by its own name: `sonelle: <prompt>`) - opens a dev session in the engine, seeded with `docs\DEVELOPING.md`; keep `selftest` green before committing.

## The three capabilities (honest about what's mechanism vs discipline)
- **Scaffold** (real mechanism) — new projects in one command, consistently structured (`tools\new_project.ps1`).
- **Heal** (real checks + detector + guided fix) — new projects ship an auto-detecting
  `sonelle.check.ps1` (npm/pytest/dotnet/cargo/go) that exits `2 = NOT configured` rather than faking
  health, and `tools\doctor.ps1` reports that honestly (plus orphaned state with no registry row). So a
  fresh project no longer reports HEALTHY while checking nothing. The diagnose->fix->verify loop is
  Claude-driven; a **Stop hook** (`.claude/settings.json`) auto-runs each project's check after every
  task (`docs\HEAL.md`).
- **Self-improve** (capture + recall as mechanism) — `tools\log_lesson.ps1` writes lessons; the
  **SessionStart hook surfaces the memory index INTO context** (not just a reminder to read it), and a
  **Stop hook** prompts capture after — so the loop runs via the harness, not just discipline
  (`docs\SELF_IMPROVE.md`). Two stores: personal /
  per-project lessons -> gitignored hub `memory/`; **generic, reusable** lessons (`-Shared`) ship IN
  the engine at `knowledge/` (public, ASCII), so a fresh clone already knows them. Hooks ship in
  `.claude/` and are scaffolded into every new project.

## Runs on your Claude subscription
The terminal hands prompts to `claude` (Claude Code), which runs on your Pro/Max plan —
**no API key needed for personal use.**

## What's inside
| Path | What |
|---|---|
| `bin\sonelle.ps1` | the terminal (Claude-styled launcher; calm welcome card, `:help` on demand; routes to `claude`) |
| `knowledge\` | the **shared knowledge base**: generic, reusable lessons (public, ASCII) that ship with the engine; personal/per-project memory stays in the gitignored hub `memory\` |
| `.claude\skills\` + `templates\skills\` | reusable **Agent Skills** claude auto-loads by task: `systematic-debugging` / `verification-before-completion` / `plan-before-build` (in the engine + every project) and `frontend-design` / `design-review` / `accessibility-audit` (scaffolded into every project) |
| `.claude-plugin\marketplace.json` + `plugin\` | this repo is also a **Claude Code plugin marketplace**: `plugin\` packages sonelle's portable **skills** so anyone can `claude plugin marketplace add <owner>/<repo>` then `claude plugin install sonelle-skills@sonelle` into their own Claude Code (no engine clone) |
| `tools\build_plugin.ps1` | regenerate `plugin\` from `templates\skills` (single source of truth; selftest enforces no drift) |
| `CLAUDE.md` | the dispatcher — how a session orients + routes |
| `PROJECTS.md` | the registry (single source of truth; starts empty) |
| `tools\new_project.ps1` | scaffold a new project (full skeleton + registry row) |
| `tools\check_pointers.ps1` | validate every registry pointer resolves |
| `tools\doctor.ps1` | health check / heal detector for a project |
| `tools\log_lesson.ps1` | capture a lesson into memory (self-improve) |
| `tools\selftest.ps1` | end-to-end self-test (dogfoods scaffold/heal into a temp hub) |
| `tools\statusline.ps1` | usage status line: 5h/7d rate-limit %, context % |
| `tools\cost.ps1` | estimate Claude token use + cost from local transcripts, per project (`:cost`) |
| `tools\repomap.ps1` | structural repo map - top-level symbols per file, a primer for large repos (`:map`) |
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
