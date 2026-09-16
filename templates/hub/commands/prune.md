---
description: Archive stale memory + ledger sections (dry-run first, then ask before applying)
---

Prune this hub's state. NEVER delete anything - prune only moves files into `_archive\`.

1. Run the dry-run and show me the report as-is:
   `powershell -NoProfile -ExecutionPolicy Bypass -File <engine>\tools\prune.ps1 -Hub <hub>`
   (`install_hub.ps1` fills both paths in when it copies this command into the workspace; if they are
   still placeholders, this file was copied by hand - re-run the installer). Check the
   `[prune] memory dir:` line - if it is not where this hub actually keeps memory, re-run with
   `-MemoryDir <dir>` before reading anything into the report.
2. Summarise it in 3 lines: how many memory files would be archived and why, how many ledger
   sections from which ledgers, and anything the lint flagged (dangling `[[links]]`, stale index
   lines, oversize `MEMORY.md`).
3. ASK me before changing anything. Do not pass `-Apply` on your own.
4. Only after I say ok, run the same command with `-Apply`, then paste the final summary.
5. If I disagree with a candidate, do not hand-edit around it - say which rule picked it
   (unregistered / closed project, section older than -Days without RESUME) and let me decide.

Notes:
- `type: feedback` and `type: user` memory is NEVER archived; it is only listed for review.
- The last 3 ledger sections (and the 3 newest by date) and anything containing RESUME stay put.
- Every run - dry or applied - writes `.claude\sonelle_prune_stamp`, which is what silences the
  "prune is due" nudge at the end of a turn.
