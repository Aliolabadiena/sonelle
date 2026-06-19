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
9. Pin to taskbar:  `powershell -File bin\make_launcher.ps1` (the `sonelle` shortcut opens the app by default; `-Terminal` for a single console), then right-click the Desktop `sonelle` shortcut -> Pin to taskbar.
10. Multi-instance:  `:team myproj bugs=opus,docs=haiku` opens parallel lanes (per-task models); `:status myproj` shows them. The orchestrator (your terminal session) always runs your max model (`opus`/`xhigh`).
11. The app (liquid glass, many terminals, one window):  type `:app` to open the desktop app - a
    frameless **Python** (pywebview / WebView2) window with a muted blue/indigo glass UI. Each tab is
    an `xterm.js` terminal; the real PowerShell (`bin\sonelle.ps1`) runs **behind the scenes** in a
    pseudo-terminal, so what you type goes to a hidden shell and the `claude` TUI works in-app.
    First run installs a local `.venv` (pywebview + pywinpty + edge-tts) - run `:app` once to watch it
    set up. Needs Python 3.10+ and the WebView2 runtime (preinstalled on Win10/11). The classic WinForms
    host is still there via `:app-classic`. `bin\make_launcher.ps1` makes the `sonelle` shortcut open the
    glass app by default (`-Classic` = WinForms, `-Terminal` = a single bare console).
    Each tab has its own **voice toggle** (a speaker on the tab pill - mute the boring research tabs,
    keep the important ones talking): turn it on and sonelle **reports her progress in a little box under
    the mascot** - **pink** when she's talking to you ("got it :)", "tests green :)") and **soft white**
    for the play-by-play - and speaks it aloud. The voice is **Kokoro**, a real local neural voice
    **bundled in the repo** (`app\voice\`, no download; `edge-tts` then Windows SAPI as fallbacks).
    Powered by Claude Code hooks; off by default, tune `narrator` in `sonelle.config.json`.
    The **mascot is her reporter**: drag it (it bounces off the edges, then drifts home), **lock** it in
    place or press **V** to open the report box, and **mute** it. Each tab keeps its own mascot
    position/state. A **settings gear** in the titlebar opens a panel for **20 colour palettes**, the
    **assistant name**, your **own mascot** image, the **reporting style** (warm/terse/hacker/bubbly),
    and the **claude model + effort**.
12. Improve sonelle itself:  type `:dev` (or address the engine by its own name: `sonelle: <prompt>`) - opens a dev session in the engine, seeded with `docs\DEVELOPING.md`; keep `selftest` green before committing.

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
| `app\` | the liquid-glass desktop app: Python (pywebview) + xterm.js front-end; PowerShell runs behind it in a PTY (`:app`) |
| `app\narrator.py` + `app\tts.py` + `app\narrate_hook.ps1` | the per-tab **voice narrator**: claude's hooks -> dual-rendered lines (a short cute **display** for the report box + a natural **speak** line for TTS, pink = she's talking to you, white = play-by-play) + **Kokoro** local-neural speech (`edge-tts`/SAPI fallback) |
| `app\ui\palettes.js` | the **20 colour palettes** for the settings panel (the gear) |
| `app\voice\` | the **Kokoro voice model vendored in the repo** (int8 `.onnx` + voice pack) - so the voice ships with sonelle, no download |
| `knowledge\` | the **shared knowledge base**: generic, reusable lessons (public, ASCII) that ship with the engine; personal/per-project memory stays in the gitignored hub `memory\` |
| `bin\sonelle_gui.ps1` | launcher for the glass app: bootstraps `.venv` (pywebview + pywinpty + edge-tts), best-effort installs the Kokoro runtime, then runs it with `pythonw` |
| `bin\sonelle_app.ps1` | the classic WinForms app host (`:app-classic`, `make_launcher -Classic`) |
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
