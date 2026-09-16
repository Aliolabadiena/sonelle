# Prune + memory lint (v1.47)

Memory files and run ledgers only ever grow. Dangling `[[links]]` in memory are worse than
missing notes: a session reads a link to a file that no longer exists and hallucinates its
contents. Two tools keep the hub honest:

| Tool | What it does | Changes files? |
|---|---|---|
| `tools\memory_lint.ps1` | lints a `memory\` dir: dangling links, stale `MEMORY.md` index, size budgets, frontmatter | only with `-Fix` |
| `tools\prune.ps1` | archives stale project memory + old ledger sections | only with `-Apply` |

Neither tool ever deletes. `prune -Apply` MOVES things into `<hub>\_archive\`.

## memory_lint.ps1

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\memory_lint.ps1 -MemoryDir <dir> [-Fix]
```

Findings are split into ISSUEs (exit 1 unless `-Fix` repairs them) and WARNs (never change the
exit code - they are budget/hygiene nags):

| Level | Finding | `-Fix` behaviour |
|---|---|---|
| ISSUE | `[[link]]` whose target file does not exist | rewritten to `(link removed: name)` |
| ISSUE | `[[a-b]]` that only resolves as `a_b` (or vice versa) | rewritten to the real file name |
| ISSUE | `MEMORY.md` index line whose `(file.md)` is missing | the line is dropped |
| WARN | memory file with no index line in `MEMORY.md` | - |
| WARN | `MEMORY.md` over 200 lines or 25 KB; index line over 150 chars | - |
| WARN | frontmatter `name:` != filename, or `description:`/`type:` missing | - |

Notes:
- `type:` is read both top-level and nested under `metadata:` - both shapes exist in the wild.
  `node_type:` is deliberately NOT treated as `type:`.
- Files are read and written as UTF-8 (PS 5.1's `Get-Content` default would mangle them), and a
  BOM is preserved if the file had one.
- Summary line: `[lint] DONE: N issue(s) (M fixed), W warning(s), dangling links: D`.

`tools\check_pointers.ps1` runs the lint report-only at the end. Warnings never fail it; a
**dangling link** does (it prints a `[MISS]` line and the script exits 1, same as a missing
pointer). That is the only way the lint changes `check_pointers` semantics.

## prune.ps1

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\prune.ps1 -Hub <hub> [-MemoryDir <dir>] [-Days 90] [-Apply] [-LedgerKB 40]
```

Dry-run by default: it prints the full plan and changes nothing except the stamp file.

An explicit `-Hub` makes the memory dir default to `<hub>\memory` (that is `Get-SonelleConfig`'s rule:
an explicit hub means a different workspace, so the config's `memoryDir` does not follow it). If that
path does not exist, prune says so and falls back to the configured `memoryDir` - pass `-MemoryDir`
when the hub keeps memory somewhere else and you want no ambiguity. The first two report lines always
name the hub and the memory dir actually used.

### memory
- `type: project`, untouched for more than `-Days`, and whose shortcode is **not** a row in
  `PROJECTS.md` **or** whose row is marked closed (`closed` / `uzdarytas` / the diacritic
  spelling, case-insensitive, matched on the Project cell) -> `<hub>\_archive\memory\`.
  The shortcode comes from the filename (`project_<short>.md`); a file that cannot be mapped is
  reported and left alone. If `PROJECTS.md` is missing, nothing is archived (fail-safe).
- `type: feedback` and `type: user` are **never** auto-archived. Past `2 x -Days` they are listed
  as `[REVIEW ]` so a human re-reads them.
- Any other/absent type is left alone.
- On `-Apply` the lint runs with `-Fix` afterwards, which drops the archived file's index line
  from `MEMORY.md`.

### ledgers
Only `<hub>\_*_run_STATUS.md` larger than `-LedgerKB` (default 40 KB) are considered.

The file is split into blocks at `## ` / `### ` headings. The heading level that actually carries
dated sections wins (real ledgers keep `## Facts / ## Gotchas / ## Runs` scaffolding and the
dated runs one level deeper at `### `; a `## `-per-run ledger works too). A section is archived
only if ALL of these hold:
- its first `YYYY-MM-DD` is older than `-Days`,
- it does not contain the word `RESUME` (unfinished work stays where the next session looks),
- it is not one of the last 3 sections in file order, and not one of the 3 newest by date
  (ledgers disagree about newest-first vs newest-last, so both ends are protected).

Archived sections are grouped by month into `<hub>\_archive\ledger\<ledger>_<yyyy-MM>.md`
(appended if the file already exists), and a one-line pointer
`(archived: N sections -> _archive\ledger\...)` is inserted at the top of the ledger, under its
title. Line endings and BOM are preserved.

### TODO files
`<hub>\*_TODO.txt`: the number of `[x]` lines is reported. Never changed automatically.

### stamp
Every run - dry or applied - writes `<hub>\.claude\sonelle_prune_stamp`. The Stop hook nudges
`/prune` when that stamp is missing or older than 30 days, so even a dry-run silences the nudge
for a month (running the report IS the point; applying is the human's call).

Exit code is always 0: a candidate is a report, not a failure.

## Cadence
Monthly, via `/prune` (the hub slash command in `templates\hub\commands\prune.md`): dry-run,
read the report, then `-Apply` once the human agrees.

## Tests
`tools\selftest.d\prune.ps1` builds a throwaway hub (memory with a dangling link, a stale closed
project, fresh feedback, an oversize index line; a >40 KB ledger with dated sections) and asserts:
lint finds exactly 3 issues and `-Fix` clears them; the variant-link rewrite; `check_pointers`
fails on a dangling link and passes once fixed; the dry-run lists 1 memory candidate, archives 0
feedback and moves nothing; `-Apply` moves the file (it exists in `_archive`, not in `memory\`),
keeps the last 3 ledger sections and the RESUME section, writes the pointer line and the stamp;
and a second dry-run is clean. Run it standalone with
`powershell -NoProfile -ExecutionPolicy Bypass -File tools\selftest.d\prune.ps1`.
