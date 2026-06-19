---
description: Verify, then commit the engine (selftest green + pure-ASCII gate)
---

Ship the current change on the engine:

1. Run `tools\selftest.ps1` - it MUST end `[selftest] ALL PASS`. If it is red, stop and fix first; never commit on red.
2. Confirm every `.ps1` you touched is pure ASCII (the house rule).
3. Add a `CHANGELOG.md` entry describing what changed and why.
4. Stage and commit with a clear message. End the message with the `Co-Authored-By` trailer.
   Commit via `git commit -F <tempfile>` (a here-string with slashes/braces breaks in PS 5.1).
5. Do NOT push unless I explicitly ask.
