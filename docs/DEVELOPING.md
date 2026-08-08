# DEVELOPING sonelle (improving the engine itself)

This guide is for working ON the engine (this repo), not for using it to run projects.
Open it via the terminal command `:dev` (which seeds a Claude session here with this context),
or read it before you `cd` into the sonelle folder and run `claude`.

> The root `CLAUDE.md` is the **dispatcher** (how a session routes PROJECTS). When you are
> developing the engine, THIS file governs the session - not the dispatcher framing.

## Session framing (how `:dev` works)
Trigger it with `:dev [prompt]` OR with the grammar using the engine's own name as the shortcode
(`<engine-name>: <prompt>`, e.g. `sonelle, sonelle: add a :foo command`) - both land here. sonelle
launches a Claude session in the engine root, seeded with these instructions. Claude Code ALSO auto-loads the root `CLAUDE.md` (the dispatcher template the engine
ships) into context - but **this file is your sole authority for the session**. If anything in
`CLAUDE.md` talks about routing a shortcode, scaffolding a project, reading hub state, or an
end-of-task ritual, **disregard it**: you are improving the ENGINE, not running a project through it.
The invariants below are absolute and override any dispatcher guidance.

## What you are touching
sonelle is the reusable ENGINE: the dispatcher, the registry format, the templates, the
scaffold/heal/self-improve tools, the terminal, and the lanes. It is a **public** repo with
**zero personal data**.

## Invariants (do NOT break these)
1. **Pure ASCII PowerShell.** PS 5.1 misreads non-ASCII in a no-BOM `.ps1`. Build any glyphs at
   runtime via `[char]` codepoints. selftest fails on any non-ASCII byte in a `.ps1`.
2. **selftest is the gate.** Run `tools\selftest.ps1` and confirm **ALL PASS** before every commit.
   If you add a feature, EXTEND selftest to cover it - the engine must stay self-verifying.
3. **No personal data, ever.** No real hub paths, project names, keys, or memory in this repo.
   `sonelle.config.json`, `memory/`, `*_TODO.txt` are gitignored on purpose - keep it that way.
4. **Do not pollute the engine with hub state.** The engine is not one of your projects. Never
   scaffold TODO / ledger / project-CLAUDE / memory into the engine root.
5. **Registry rows only via `new_project.ps1`** (fixed column shape; never hand-edit rows).
6. **Keep the split:** root `CLAUDE.md` = the dispatcher (and the template a hub adopts);
   `templates\CLAUDE.template.md` = the per-project skeleton. Do not merge these two roles.

## Workflow
1. Read `docs\ARCHITECTURE.md` first (how the pieces fit + the CLAUDE.md load behavior).
2. Make the change. Match the existing style (ASCII; the palette + format-string `Write-Host` calls).
3. `tools\selftest.ps1` -> ALL PASS. Red = fix or revert; never commit red.
4. Commit + push to the public repo. Everything is git-versioned, so **rewind freely** -
   experiment, and `git revert` / `git reset` if a direction turns out wrong.
5. Capture lessons. A **generic, cross-project** lesson (no personal data) ships IN the engine via
   `tools\log_lesson.ps1 -Shared` -> `knowledge\` (public, ASCII, indexed by `knowledge\INDEX.md`); a
   **personal / per-project** lesson goes to YOUR gitignored hub `memory\` (default, no `-Shared`). The
   shared `knowledge\` base is curated engine content (like `docs\`/`templates\`), NOT hub state - so it
   does not violate invariant 4; just keep it personal-data-free. The SessionStart hook recalls both.

## Common changes
- **New terminal command:** add a handler in the REPL loop of `bin\sonelle.ps1`, a line in
  `ShowHelp`, and a selftest assertion that the handler exists.
- **Terminal UI:** the launch screen is `Welcome` (a minimal rounded card - brand, live project list,
  one example, footer); the full command list lives in `ShowHelp` (`:help`, on demand) - keep the two
  split (don't move the command dump back into the welcome). Box glyphs are built at runtime via
  `[char]` codepoints (e.g. `0x256D`); never paste a non-ASCII glyph into the source. selftest 8b
  guards the welcome (brand shown, no command dump) and that `:help` still lists every command.
- **New tool:** add `tools\<name>.ps1` (ASCII, `$ErrorActionPreference='Stop'`, `-Hub`-aware if it
  touches hub state), wire it where it is used, and cover it in selftest.
- **New template:** add it to `templates\`, have `new_project.ps1` write it, and assert it
  scaffolds in selftest.
- **Self-develop routing:** the shortcode that makes `<engine-name>: <prompt>` reach `:dev` is derived
  from the engine FOLDER name, lowercased (`$script:selfShort` in `bin\sonelle.ps1`), and special-cased in
  `Route` BEFORE the registry lookup - so it never pollutes `PROJECTS.md`, and renaming the engine folder
  updates it automatically.
- **Yolo (skip permission prompts):** `SONELLE_YOLO=1` / `-Yolo` / `:yolo` / the config key
  `models.orchestratorPermissionMode` all funnel through `$orchPerm` in `sonelle.ps1` ->
  `claude --permission-mode bypassPermissions`.
- **The model split (config):** the **orchestrator** model + effort (`models.orchestrator`/
  `orchestratorEffort` -> `--model`/`--effort`) and a separate **code-writer** model
  (`models.codeWriter`, `inherit`/empty = same) that `bin\sonelle.ps1` exports as
  `CLAUDE_CODE_SUBAGENT_MODEL` so claude's file-editing SUBAGENTS run on their own model.
  **These are LIVE:** `RefreshOrch` in `bin\sonelle.ps1` re-reads the model block right before each
  `claude` launch (Route + DevSelf), so a config edit applies to the NEXT prompt - the config file is
  the channel (and `$env:SONELLE_CONFIG` can repoint that file; the resolver in `tools\_registry.ps1`
  honors it, which is also how selftest 5d stays hermetic). Permission mode is NOT re-read live (it
  has `-Yolo`/`:yolo` overrides). Guarded by selftest 5d (behavioral: model/effort/code-writer +
  SONELLE_CONFIG). NOTE (2026-08): `CLAUDE_CODE_SUBAGENT_MODEL` still works but is no longer
  prominent in the docs - the modern per-subagent mechanism is a `model:` field in
  `.claude/agents/<name>.md` frontmatter. If the env var ever stops routing, migrate there.
- **Guard hook + slash commands + inherent altitude (v1.36):** the engine and every scaffolded project
  ship a **PreToolUse guard** (`.claude\hooks\pretooluse_guard.ps1`, wired in `.claude\settings.json` for
  `Write|Edit|Bash`). It reads claude's UTF-8 payload on stdin (`OpenStandardInput` as UTF-8 - PS 5.1's
  `[Console]::In` uses the console code page and would corrupt non-ASCII), and on a violation EXITS 2 to
  BLOCK the call (stderr goes back to claude); any parse/read problem EXITS 0 (a guard must never break a
  session). This is the only guardrail left in a `bypassPermissions` session. The ENGINE guard enforces
  the house rule (no non-ASCII written to a `.ps1`) and invariant #4 (no `new_project`, no plain
  `log_lesson` - only `-Shared` -> `knowledge\`; no `*_TODO.txt`/`*_run_STATUS.md`/`memory\` at the engine
  root) plus blocks force-push; the PROJECT template guard blocks force-push and is a stub to add your own
  rules. **Slash commands** (`.claude\commands\`: `/selftest /heal /ship /ritual`) codify the rituals -
  engine versions drive `selftest`/`doctor`/the commit gate, scaffolded versions drive `sonelle.check.ps1`
  + the project's TODO/ledger. **Inherent operating policy (v1.36, broadened v1.38):** `bin\sonelle.ps1`
  appends a one-line policy (`$operatingPolicy`) to EVERY project/engine session via `--append-system-prompt`
  so claude PROACTIVELY picks the workflow from the task alone (the user states the goal, not the tool):
  delegate breadth-first exploration to subagents on a hard / multi-file task and do small ones directly;
  VERIFY after a change by running the right check (selftest or `sonelle.check.ps1`); HEAL on failure; run the
  end-of-task ritual when done - while scaling down so a one-liner gets no ceremony. The `general:` lane gets
  a minimal `$generalDirective` instead (no project state to maintain). DevSelf also moves its engine framing
  into `--append-system-prompt` (the
  system prompt survives compaction better than a user-turn seed). Both gate on a cached
  `ClaudeSupports '--append-system-prompt'` probe and fall back to folding the text into the prompt on an
  older `claude`. Guarded by selftest 8h (guard exists + behavioral block/allow incl. the non-ASCII case +
  commands + wiring) and 5d (routing attaches `--append-system-prompt`).
- **Onboarding + :adopt + general (v1.37):** `-Bare` mode prints a
  tiny no-claude primer (`BareIntro`: `:new` / `:adopt` / `<short>: <prompt>` / connect claude); bare
  `help`/`help:`/`?` shows `ShowHelp` and never routes. **`:adopt <path> [as <short>]`** (`Adopt` in
  `bin\sonelle.ps1`) scaffolds the skeleton over an EXISTING repo then `Route`s an AI conversion prompt
  into it - non-destructive (existing `CLAUDE.md`/`sonelle.check.ps1`/`.claude\` are copied to
  `*.pre-sonelle.bak` first). **`general: <prompt>`** is intercepted in `Route` -> `General`, which runs
  claude in `%TEMP%\sonelle_general` (neutral - no `CLAUDE.md` up the tree) with NO hub state / registry
  row / memory; `general` is a reserved shortcode (new_project refuses it). Guarded by selftest 5f
  (behavioral) + 8b.
- **Docs:** keep `README.md` + `docs\ARCHITECTURE.md` honest (mechanism vs discipline), and add a
  `CHANGELOG.md` entry.

## Releasing
Bump `CHANGELOG.md` (new top entry), keep README's "What's inside" table current, run selftest,
commit, push. There are no version tags yet - the CHANGELOG is the source of truth.
