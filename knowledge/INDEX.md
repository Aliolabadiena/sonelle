# sonelle knowledge - reusable lessons (ships with the engine)

Generic, cross-project lessons that help on ANY project, versioned IN the engine. This is sonelle's
shared, file-based brain - it travels with the repo, so a fresh clone already knows them. It is a
PUBLIC, pure-ASCII, ZERO-personal-data space: only put lessons here that are useful everywhere and
contain no names, paths, keys, or project specifics.

It is deliberately separate from your **personal / per-project memory**, which stays in the
gitignored hub `memory/` (and your Claude auto-memory). Rule of thumb:

- A lesson useful on **any** project, with no personal data -> here (`knowledge/`, committed).
- A fact about **you** or **one project** (paths, names, preferences, ongoing work) -> hub `memory/`.

## Using it
- **Recall:** skim this index at the start of a task (the SessionStart hook points here).
- **Capture (shared):** `tools\log_lesson.ps1 -Shared -Slug <slug> -Desc "..." -Body "..."` adds a
  generic lesson here and links it below. (No `-Shared` -> a personal lesson in the hub `memory/`.)

## Lessons
- [powershell-commit-heredoc](powershell-commit-heredoc.md) - PS 5.1 `git commit -m @'...'@` with slashes/braces fails; commit via `git commit -F <tempfile>`.
- [powershell-pure-ascii](powershell-pure-ascii.md) - PS 5.1 misreads non-ASCII in a no-BOM .ps1; build glyphs at runtime from [char] codepoints.
- [powershell-case-insensitive-vars](powershell-case-insensitive-vars.md) - $Hub and $hub are ONE variable; reassigning a same-name-different-case working var clobbers a parameter override.
- [selftest-grep-assertion-self-collision](selftest-grep-assertion-self-collision.md) - source-grep assertions can match comments / their own wording; anchor on a unique code-only token and watch negative matches.
