---
name: ps-hook-stdin-utf8
description: PS 5.1 hooks must read stdin as UTF-8; testing a stdin filter from PS mangles non-ASCII (OutputEncoding) and can throw on stderr (EAP=Stop)
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

**Why:** Without the explicit UTF-8 read a PreToolUse ASCII-guard passes non-ASCII through; and the two test traps make a CORRECT guard look broken.
**How to apply:** Hook: $raw = (New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [Text.Encoding]::UTF8)).ReadToEnd(). Test: feed raw UTF-8 bytes via cmd type, 2>nul the hook stderr, keep exit codes for assertions.


**Why:** Without the explicit UTF-8 read a PreToolUse ASCII-guard passes non-ASCII through; and the two test traps make a CORRECT guard look broken.
**How to apply:** Hook: $raw = (New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [Text.Encoding]::UTF8)).ReadToEnd(). Test: feed raw UTF-8 bytes via cmd type, 2>nul the hook stderr, keep exit codes for assertions.
