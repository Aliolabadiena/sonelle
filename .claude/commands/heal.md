---
description: Run doctor and fix every problem until the engine is healthy
---

Heal the engine (see `docs\HEAL.md`):

1. Run `tools\doctor.ps1`.
2. For each problem it reports, find the root cause and fix it - do not paper over it.
3. Re-run `tools\doctor.ps1` and repeat until it reports healthy.
4. Then run `tools\selftest.ps1` and confirm ALL PASS.
