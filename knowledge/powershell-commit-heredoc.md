---
name: powershell-commit-heredoc
description: PS 5.1 `git commit -m @'...'@` with slashes/braces fails; commit via `git commit -F <tempfile>`.
metadata:
  type: reference
---

On Windows PowerShell 5.1, passing a multi-line commit message to `git commit -m` through a
single-quoted here-string (`@'...'@`) can fail with `fatal: <path>: outside repository` when the
message body contains slashes or braces - PowerShell mangles the argument before git ever sees it.

**Why:** 5.1's argument handling corrupts a here-string passed to a native exe (slashes/braces get
reinterpreted), so git receives a broken arg list.
**How to apply:** write the message to a temp file and commit with `git commit -F <tempfile>` (or
pipe it via `git commit -F -`). Avoid `-m @'...'@` for anything multi-line on 5.1.
