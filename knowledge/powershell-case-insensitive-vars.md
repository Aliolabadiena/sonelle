---
name: powershell-case-insensitive-vars
description: PowerShell variable names are case-insensitive; a param like $Hub and a working var $hub are ONE slot - reassigning one clobbers the other.
metadata:
  type: reference
---

PowerShell variable names are **case-insensitive**, so `$Hub` and `$hub` (or `$R` and `$r`) refer to the
SAME variable. A classic trap: a script takes a parameter `[string]$Hub`, then a few lines later sets a
working variable `$hub = $root`. That assignment silently overwrites the parameter value - so an explicit
`-Hub <path>` override is lost and the code falls back to the default, with no error.

**Why:** the language treats identifiers case-insensitively; differing only by case does NOT create a new
variable, it aliases the existing one. The bug is invisible because nothing throws - the override just
never takes effect.
**How to apply:** never let a parameter and a working variable differ only by case. Either (a) read the
parameter and assign the working variable BEFORE any reassignment, (b) capture the param into a distinctly
named local first (e.g. `$hubOverride = $Hub`) and use that, or (c) name them unambiguously. A behavioral
test (drive the code and assert the override actually took effect) catches this where a source grep can't.
See also [[powershell-pure-ascii]].
