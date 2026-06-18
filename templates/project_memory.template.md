---
name: project_{{SHORT}}
description: {{NAME}} ({{SHORT}}) — project state and gotchas; sources {{SHORT_UPPER}}_TODO.txt + _{{SHORT}}_run_STATUS.md
metadata:
  type: project
---

{{NAME}} ({{SHORT}}) — created {{DATE}}. Code: `{{PATH}}`.

Live state lives in files (NOT here): `{{SHORT_UPPER}}_TODO.txt` + `_{{SHORT}}_run_STATUS.md`.
Onboarding: `{{PATH}}\CLAUDE.md`. Registry: `PROJECTS.md`.

**How to open:** message `{{SHORT}}: <prompt>` -> the dispatcher reads the sources,
confirms state in one line, then works.

**Lessons (self-improve):** append gotchas / feedback / dead-ends here as they're learned,
so future sessions recall them before starting.
