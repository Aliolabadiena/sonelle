# {{NAME}} ({{SHORT}}) — project onboarding

> Pointers, not content. Live state lives in the files below, refreshed after every
> task. Never guess state from memory — read the sources first.

## State sources (read FIRST)
- Tasks: `{{SHORT_UPPER}}_TODO.txt`
- Run ledger: `_{{SHORT}}_run_STATUS.md`
- Memory: `memory/project_{{SHORT}}.md`
- Registry row: `PROJECTS.md`

## Code path
- `{{PATH}}`

## Rules (fill in as the project grows)
- Keys / permissions: -
- Build / run commands: -
- Health check (used by `tools\doctor.ps1`): -
- Gotchas: -

## Before starting (recall)
Skim `memory/MEMORY.md` and open any relevant topic file; verify memory claims against current
code before relying on them. (sonelle self-improve = recall before, capture after.)

## Waves (when the task is too big for one context)
brief -> implement (`implementer`, DISJOINT file ownership) -> review (`reviewer`, read-only, against the
brief) -> fix (`implementer`) -> verify (`verifier`) -> run the project check. The agent definitions live
in `.claude/agents/`; if the workspace has the sonelle hub hooks installed, DELEGATE mode, HOLD
("palauk"), model tiering and the read-only reviewers are enforced by hooks, not goodwill.

## Work cycle
- Collect: only record dictated items into the TODO; don't start work mid-collection.
- "start" -> ask all questions + permissions in one batch, then work autonomously.

## End-of-task ritual
Update TODO ([x] + note) and ledger (done + gotchas + RESUME if unfinished); SELF-IMPROVE
(capture lessons into memory); validate pointers. Never leave knowledge only in chat.
