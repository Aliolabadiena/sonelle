# Changelog

## v1.2 — 2026-06-18 (skeptical-audit fixes)
- **SECURITY:** `.gitignore` had trailing inline comments (git treats `pattern  # x` as a literal
  filename), so `luna.config.json` / `memory/` / `*_TODO.txt` were NOT ignored - a `git add -A`
  could have leaked a hub's brain to the public repo. Comments moved to their own lines; verified
  via `git check-ignore` (now a selftest gate).
- **check_pointers** silently validated ZERO projects: its `([^\r\n]*)$` row regex didn't match the
  CRLF rows `new_project` wrote. Root cause was 4 divergent registry regexes; replaced with ONE
  shared CRLF-safe parser `tools\_registry.ps1` used by check_pointers, doctor, and the terminal.
- **selftest** now proves the validator actually works: asserts check_pointers flips to exit 1 on a
  deleted code path, and asserts `.gitignore` ignores the private paths. Both critical bugs would now fail the test.
- `log_lesson.ps1` gained `-Hub` (was writing memory into the engine, not the hub).
- `new_project` normalizes line endings (LF) so it never writes mixed CRLF/LF again.
- Terminal: safe address-strip (only strips a leading `addr,` before a real `short:`; no more
  mangling prose with commas); `@path` only stripped when it's a real file (emails/@handles/decorators
  survive); echoes the final prompt before handing to `claude`; lowercases the shortcode; enables VT /
  falls back to no-color (respects `NO_COLOR`).
- `doctor`: guards missing `git`/`PROJECTS.md`, adds an environment preflight (PowerShell + `claude`
  on PATH), and distinguishes HEALTHY from NOTHING-CHECKED (empty registry no longer reads green).
- Docs made honest: "any machine" -> "any Windows machine + prereqs"; HEAL = detect + manual fix;
  SELF-IMPROVE = capture + discipline (not engine-enforced); documented CLAUDE.md auto-load behavior.

## v1.1 — 2026-06-18
- `-Hub` threading across `new_project` / `check_pointers` / `doctor` + the terminal, so one
  engine can drive a separate workspace coherently.
- Engine vs hub separation: templates are read from the engine, state is written to the hub
  (fixes scaffolding into an external `-Hub`).
- Terminal: image attach via `:attach <path>` and inline `@<path>`; `:clear`.
- `tools\selftest.ps1` + `luna.check.ps1`: end-to-end self-test (parse/ASCII/scaffold/
  check_pointers/doctor/duplicate-guard) into a throwaway temp hub. All pass.
- Fixed `$args` automatic-variable shadowing in the terminal's heal path.

## v1.0 — 2026-06-18
- Dispatcher (`CLAUDE.md`) + registry (`PROJECTS.md`) + grammar `[address,] <short>: <prompt>`.
- Claude-styled terminal `bin\luna.ps1` (routes to `claude`, runs on a Claude subscription).
- Three superpowers: scaffold (`new_project`), heal (`doctor` + `docs\HEAL.md`),
  self-improve (`log_lesson` + `docs\SELF_IMPROVE.md`).
- Templates, docs (`HEAL`, `SELF_IMPROVE`, `ARCHITECTURE`). Pure-ASCII PowerShell.
