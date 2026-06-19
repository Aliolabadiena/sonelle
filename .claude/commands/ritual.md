---
description: Run the engine end-of-task ritual (selftest, changelog, capture the lesson)
---

Close out this task on the engine:

1. Make sure `tools\selftest.ps1` is ALL PASS - if you added a feature, you must have extended selftest to cover it.
2. Add or update the `CHANGELOG.md` entry for this change.
3. If you learned something reusable (a gotcha, a fix, feedback), capture it with
   `tools\log_lesson.ps1 -Shared` into `knowledge/` - never leave knowledge only in chat.
4. If anything is unfinished, say exactly what remains and the next concrete step.
