---
name: selftest-grep-assertion-self-collision
description: source-grep selftest assertions can match comments / their own wording; anchor on a unique token and watch negative matches.
metadata:
  type: gotcha
---

selftest assertions that prove a feature by grepping the source (`-match`, `Select-String`,
`.IndexOf(...)`) are fragile in two ways that BOTH bit a real run:

1. **Substring matches a comment, not the code.** An "order" check `IndexOf('app.js') < ...` matched
   the literal `app.js` inside an HTML *comment* ("see app.js wireBrandloopDrag"), not the
   `<script src="app.js">` tag, so a true ordering read as false. Anchor on a token that ONLY appears
   in the thing you mean - e.g. `IndexOf('src="app.js"')`, or a function signature, not a bare name.

2. **A negative assertion collides with your own wording.** `-not ($src -match 'selfShort')` (meant to
   prove the customization code never touches the engine self-short) failed because a nearby *comment*
   literally said "never touches the ... selfShort". A `-not match` over a whole file catches matches
   anywhere, including comments you wrote to describe the very guarantee.

**Why:** these tests read flat source text, not an AST, so any occurrence anywhere counts.
**How to apply:** anchor positive checks on a unique, code-only token (a tag with quotes, a full
signature). For a "code never does X" guard, don't let the assertion's own subject appear verbatim in a
comment - reword the comment, or assert on the specific call you forbid rather than a bare identifier.
Run selftest after adding an assertion; a self-collision shows up immediately as a paradoxical FAIL.
