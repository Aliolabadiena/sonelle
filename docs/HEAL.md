# HEAL — fixing errors in a project

sonelle's healing is a loop: a script **detects**, Claude **fixes**. No magic — a tight,
repeatable diagnose->fix->verify cycle.

## The loop
1. **Detect** — run `tools\doctor.ps1 [<short>]`. It checks:
   - registry pointers resolve (`check_pointers.ps1`),
   - the hub git tree (clean / dirty),
   - each project's code path exists,
   - each project's own checks via the hook `<code path>\sonelle.check.ps1` (exit 0 = healthy).
2. **Diagnose** — for each `[FAIL]`, read the failing area (the test output, the missing
   file, the broken pointer). Find the ROOT cause, not the symptom.
3. **Fix** — make the smallest correct change.
4. **Verify** — re-run `doctor.ps1`. Repeat until `HEALTHY (0 fails)`.
5. **Record** — capture any non-obvious cause/fix as a lesson (`log_lesson.ps1`) so the
   same break doesn't get re-discovered next time (see SELF_IMPROVE.md).

## Define a project's health (`sonelle.check.ps1`)
Put real checks in `<code path>\sonelle.check.ps1` — whatever proves the project is healthy.
Exit non-zero on failure. Examples:
- a test suite: `npm test` / `flutter test` / `pytest` -> propagate the exit code.
- a build smoke / typecheck / linter.
- a data integrity probe.

```powershell
# example sonelle.check.ps1
$ErrorActionPreference = 'Stop'
npm test
exit $LASTEXITCODE
```

## Principle
A fix isn't done until the detector that would have caught it passes. If nothing would
have caught it, add a check first — then fix.
