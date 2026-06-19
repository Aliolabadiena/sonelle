---
name: hermetic-config-test-env-override
description: Make config-dependent behavioral tests hermetic with an env path override
metadata:
  type: gotcha
---

---
name: {{SLUG}}
description: {{ONE_LINE}}
metadata:
  type: {{TYPE}}
---

{{BODY}}

**Why:** 
**How to apply:** If a behavioral test reads a real config/state file, add an env override for its path and point the test at a fixture; save/restore the env var.


**Why:** 
**How to apply:** If a behavioral test reads a real config/state file, add an env override for its path and point the test at a fixture; save/restore the env var.
