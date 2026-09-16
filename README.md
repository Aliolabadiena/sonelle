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
7. *(recommended)* Install the **enforcement layer** into your hub:
   `powershell -File tools\install_hub.ps1 -Hub <your hub> -Canary "Name," -Owner "Name"`
   - five guard hooks + the `/prune` command + the review-only subagents land in `<hub>\.claude\`
   (idempotent; `-Uninstall` removes exactly what it added). What each guard blocks and how to turn one
   off: `docs\ENFORCEMENT.md`.
8. Verify the engine:  `powershell -File tools\selftest.ps1`
9. Improve sonelle itself:  open Claude Code **in the engine folder** - `docs\DEVELOPING.md` carries the
   engine-dev invariants. Keep `selftest` green before committing.

**Parallelism is native now.** Run several workstreams with Claude Code's own Agent / Workflow tools,
or open more than one session on git worktrees with disjoint file ownership. sonelle no longer ships a
lane launcher of its own - what it does ship is the **wave pattern** and the named subagents that make it
safe: `implementer` (writes, disjoint files), `reviewer` / `verifier` (**read-only**, enforced by their
`tools:` allowlist and by a hook) and `scout` (cheap recon). See `docs\AGENTS.md`.

## The three capabilities (honest about what's mechanism vs discipline)
- **Scaffold** (real mechanism) — new projects in one command, consistently structured (`tools\new_project.ps1`).
- **Heal** (real checks + detector + guided fix) — new projects ship an auto-detecting
  `sonelle.check.ps1` (npm/pytest/dotnet/cargo/go) that exits `2 = NOT configured` rather than faking
  health, and `tools\doctor.ps1` reports that honestly (plus orphaned state with no registry row). So a
  fresh project no longer reports HEALTHY while checking nothing. The diagnose->fix->verify loop is
  Claude-driven; a **Stop hook** (`.claude/settings.json`) auto-runs each project's check after every
  task (`docs\HEAL.md`).
- **Enforce** (v1.47, real mechanism) - the rules that kept being re-stated in prose are hooks now:
  `tools\install_hub.ps1 -Hub <hub>` installs five PreToolUse/UserPromptSubmit/Stop guards into a hub -
  a **HOLD** ("palauk" = full stop for every tool), **delegate-by-default** (in DELEGATE mode the main
  agent briefs a subagent instead of editing code, by hand or through a shell), **model tiering**,
  **review-only** reviewer/verifier subagents, and a Stop check that a turn ends with text (plus an
  optional canary). All fail-open; all covered behaviorally by selftest (`docs\ENFORCEMENT.md`).
- **Self-improve** (capture + recall as mechanism) — `tools\log_lesson.ps1` writes lessons; the
  **SessionStart hook surfaces the memory index INTO context** (not just a reminder to read it), and a
  **Stop hook** prompts capture after — so the loop runs via the harness, not just discipline
  (`docs\SELF_IMPROVE.md`). Two stores: personal /
  per-project lessons -> gitignored hub `memory/`; **generic, reusable** lessons (`-Shared`) ship IN
  the engine at `knowledge/` (public, ASCII), so a fresh clone already knows them. Hooks ship in
  `.claude/` and are scaffolded into every new project. Memory only grows, so `tools\prune.ps1` +
  `tools\memory_lint.ps1` (the `/prune` command) archive stale project memory and ledger sections and fix
  dangling `[[links]]` - never deleting, only moving (`docs\PRUNE.md`).

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
| `tools\selftest.ps1` | end-to-end self-test (dogfoods scaffold/heal into a temp hub; `tools\selftest.d\*.ps1` are its sections) |
| `tools\install_hub.ps1` + `templates\hub\` | install the enforcement layer (five hooks + `settings.json` merge + `/prune` + agents) into a hub; `-Uninstall` reverses it |
| `templates\agents\` + `.claude\agents\` | the named subagents: `reviewer` / `verifier` (read-only), `implementer`, `scout` - copied into every hub and every new project |
| `tools\prune.ps1` + `tools\memory_lint.ps1` | archive stale memory / ledger sections (never delete) + lint dangling `[[links]]` and the memory index |
| `tools\statusline.ps1` | usage status line: 5h/7d rate-limit %, context % |
| `tools\cost.ps1` | estimate Claude token use + cost from local transcripts, per project |
| `tools\repomap.ps1` | structural repo map - top-level symbols per file, a primer for large repos |
| `sonelle.check.ps1` | the engine's own health check (runs the self-test) |
| `.claude\hooks\` + `.claude\commands\` | the PreToolUse guard + `/selftest /heal /ship /ritual`, scaffolded into every project |
| `assets\icon\` | project icon: `sonelle.svg` (vector) + `make_icon.py` -> `sonelle.ico` / `sonelle.png` |
| `templates\` | project skeletons used by `new_project` |
| `docs\` | `HEAL.md`, `SELF_IMPROVE.md`, `ARCHITECTURE.md`, `DEVELOPING.md` (how to improve the engine), `ENFORCEMENT.md` (the hooks), `AGENTS.md` (the subagents + the wave pattern), `PRUNE.md` (memory hygiene), `HOOK_PAYLOADS.md` (what a hook actually receives) |

## Engine vs hub (where things live)
The **engine** assets (this repo: `tools/`, `templates/`, `docs/`, `.claude/`) are always read
from where the scripts live. Your **hub** (the `CLAUDE.md` + `PROJECTS.md` + `memory/` +
per-project state) is where work lands — by default the engine folder, or any path you pass
via `-Hub` / `sonelle.config.json`. So you can drive a separate workspace with one engine.

## Notes
- PowerShell scripts are **pure ASCII on purpose** (Windows PowerShell 5.1 misreads
  non-ASCII in a no-BOM `.ps1` and breaks parsing). Keep them ASCII.
- Your projects, memory, and state live in your own hub — **separate from this engine.**
