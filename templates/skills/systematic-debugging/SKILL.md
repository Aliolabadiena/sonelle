---
name: systematic-debugging
description: Find the root cause with evidence before proposing any fix. Use when something is broken or failing, a test is red, there is an error or stack trace, a crash, or a regression ("why does X happen", "it stopped working"). Do NOT use for greenfield feature work or an obvious known one-line typo.
---

# Systematic debugging

Iron rule: NO FIX WITHOUT A ROOT CAUSE FOUND FIRST. Guessing and stacking patches wastes time
and hides the real defect. Work the phases in order; do not jump ahead to a fix.

## Phase 1 - Root cause (hard gate: no fix may be proposed until this is done)
- Read the FULL error and stack trace, not just the last line.
- Reproduce it consistently; note the exact steps and inputs that trigger it.
- Check what changed recently (git log / git blame on the failing area).
- Add evidence at the boundaries (log/print values where data crosses a function or module).
- Trace the bad value BACKWARD up the call stack to where it first goes wrong.

## Phase 2 - Compare against something that works
- Find a similar path in the codebase that DOES work.
- Compare it line by line with the broken path; list every difference, however small.

## Phase 3 - One hypothesis at a time
- State one specific, testable hypothesis for the cause.
- Change ONE thing to test it. If it does not fix it, REVERT and form a new hypothesis.
- Never apply several speculative changes at once - you will not know which one mattered.

## Phase 4 - Fix and prove
- Write (or identify) a test that fails because of the bug.
- Apply the single fix that addresses the root cause.
- Run the test/check, read the output AND the exit code, and confirm it now passes.

## Architecture gate
If three fixes in a row fail, STOP patching and question the design - repeated failure usually
means a structural problem, not a local bug.

## Red flags (stop if you catch yourself doing these)
Reaching for a quick patch, changing several things at once, skipping the proving test, or
attempting a fourth fix on the same spot.
