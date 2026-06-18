# Changelog

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
