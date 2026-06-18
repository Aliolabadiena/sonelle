# Projects registry — single source of truth

The sonelle dispatcher (`CLAUDE.md`) reads this every session to route a request to the
right project. Add rows ONLY via `tools\new_project.ps1` (don't hand-edit the row
format — the dispatcher and `check_pointers.ps1` parse it).

**Grammar:** `[address,] <shortcode>: <prompt>`  — e.g. `sonelle, myproj: fix the build`

## Registry

| Shortcode | Project | Code path | Git | State sources (read FIRST) | Keys / notes |
|---|---|---|---|---|---|
