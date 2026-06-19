---
name: powershell-pure-ascii
description: PS 5.1 misreads non-ASCII in a no-BOM .ps1; build glyphs at runtime from [char] codepoints.
metadata:
  type: reference
---

Windows PowerShell 5.1 treats a `.ps1` with no byte-order mark as ANSI (the system codepage), not
UTF-8. So any non-ASCII byte in the source - box-drawing, arrows, emoji, smart quotes - is misread,
which can corrupt output or break parsing entirely.

**Why:** 5.1 defaults to the legacy ANSI codepage for BOM-less scripts; the bytes are decoded wrong.
**How to apply:** keep `.ps1` source pure ASCII and build any glyph at runtime from its codepoint,
e.g. `[char]0x2192` (arrow) or `[char]0x256D` (box corner). (Saving UTF-8 *with* a BOM also works,
but pure-ASCII source is the most portable.)
