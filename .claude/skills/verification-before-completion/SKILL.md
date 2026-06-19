---
name: verification-before-completion
description: Prove a claim with a fresh command run before saying it is done, fixed, passing, or working. Use before reporting completion, before a commit or PR, and before trusting a subagent's success report. Do NOT skip for "small" or "obvious" changes.
---

# Verify before claiming done

Rule: NO COMPLETION CLAIM WITHOUT FRESH VERIFICATION EVIDENCE. The worst failure for a
self-driving assistant is a confident "it works" that was never actually checked.

## The gate (run every step, in order)
1. Name the command that actually PROVES the claim (the test, the build, the health check).
2. Run it fresh and let it finish - do not reuse stale output from earlier.
3. Read the FULL output and the exit code.
4. Confirm the output really matches the claim (not just "it did not crash").
5. Only then state it is done, and cite the evidence (what you ran, what it showed).

## Windows / PowerShell note
After a native command, trust the numeric exit code via $LASTEXITCODE, NOT $?. In PS 5.1,
redirecting a native command's stderr can set $? to false even on a clean exit 0.

## Red-flag phrases that mean you have NOT verified
"should work", "probably", "I think", "Done!" / "Great!" before running anything, asserting a
pre-commit state without testing, trusting a subagent's "success" without your own check, or
verifying one case and extrapolating to the rest.

No exceptions for being tired, being confident, or "just this once".
