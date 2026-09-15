# sonelle

A reusable **engine** for running many projects through one orchestrator (Claude):
zero-hallucination onboarding, project **healing**, and **self-improvement from memory**.

> sonelle is the ENGINE, not your data. Projects you create with sonelle are separate from
> sonelle and never live in this repo. This repo contains **no personal information**.

## Quick start
1. Clone this repo. **Prereqs:** **Claude Code** (the desktop app or the `claude` CLI, logged into
   your Claude subscription), Windows + PowerShell 5.1+ for the tools, and `git`. macOS/Linux are
   not supported yet (the tools are PowerShell-only).
2. *(optional)* copy `sonelle.config.example.json` -> `sonelle.config.json` and set `hub` to
   your workspace path (where `CLAUDE.md` + `PROJECTS.md` + `memory/` live). Default `.`
   = this folder. If your project memory lives OUTSIDE `<hub>/memory` (e.g. a Claude Code memory
   dir), set `memoryDir` to that path so heal/validate resolve memory pointers correctly.
   `sonelle.config.json` is gitignored, so your local paths never enter the repo.
3. Open **Claude Code in your hub folder**. It loads `CLAUDE.md` (the dispatcher) and `PROJECTS.md`
   (the registry) and does the routing itself — that is the whole interface.
4. Create a project:  `powershell -File tools\new_project.ps1 <short> "<name>" "<path>"`
   (or just use a shortcode that isn't in the registry yet: the dispatcher offers to scaffold it).
5. Work:  type `myproj: do the thing` — the session reads that project's state first, then works.
6. Attach an image:  drop it into the Claude Code prompt, or name the path in the message.
7. Verify the engine:  `powershell -File tools\selftest.ps1`
8. Improve sonelle itself:  open Claude Code **in the engine folder** - `docs\DEVELOPING.md` carries the
   engine-dev invariants. Keep `selftest` green before committing.

**Parallelism is native now.** Run several workstreams with Claude Code's own Agent / Workflow tools,
or open more than one session on git worktrees with disjoint file ownership. sonelle no longer ships a
lane launcher of its own.

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
You work in Claude Code, which runs on your Pro/Max plan — **no API key needed for personal use.**
sonelle adds no billing path of its own; it is files and PowerShell tools that the session uses.

## What's inside
| Path | What |
|---|---|
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
| `tools\cost.ps1` | estimate Claude token use + cost from local transcripts, per project |
| `tools\repomap.ps1` | structural repo map - top-level symbols per file, a primer for large repos |
| `sonelle.check.ps1` | the engine's own health check (runs the self-test) |
| `.claude\hooks\` + `.claude\commands\` | the PreToolUse guard + `/selftest /heal /ship /ritual`, scaffolded into every project |
| `assets\icon\` | project icon: `sonelle.svg` (vector) + `make_icon.py` -> `sonelle.ico` / `sonelle.png` |
| `templates\` | project skeletons used by `new_project` |
| `docs\` | `HEAL.md`, `SELF_IMPROVE.md`, `ARCHITECTURE.md`, `DEVELOPING.md` (how to improve the engine) |

## Engine vs hub (where things live)
The **engine** assets (this repo: `tools/`, `templates/`, `docs/`, `.claude/`) are always read
from where the scripts live. Your **hub** (the `CLAUDE.md` + `PROJECTS.md` + `memory/` +
per-project state) is where work lands — by default the engine folder, or any path you pass
via `-Hub` / `sonelle.config.json`. So you can drive a separate workspace with one engine.

## Notes
- PowerShell scripts are **pure ASCII on purpose** (Windows PowerShell 5.1 misreads
  non-ASCII in a no-BOM `.ps1` and breaks parsing). Keep them ASCII.
- Your projects, memory, and state live in your own hub — **separate from this engine.**
