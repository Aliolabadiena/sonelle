# AGENTS - the four named subagents (review-only enforcement)

Adversarial review used to be a *convention*: "send a fresh agent, tell it not to edit". A prompt is
not enforcement. These four agent definitions make the roles **structural** - a reviewer has no edit
tools at all, so it cannot write even if it decides to.

Source of truth: `templates\agents\*.md`. The engine carries byte-identical copies in
`.claude\agents\` (so engine-dev sessions get the same roles), `tools\install_hub.ps1` copies them
into a hub's `.claude\agents\`, and `tools\new_project.ps1` scaffolds them into every new project.

## The roster

| agent | model / effort | tools | use it for |
|---|---|---|---|
| `reviewer` | opus / high | Read, Grep, Glob, Bash, WebFetch | adversarial review of a wave against its spec; returns findings + evidence |
| `verifier` | opus / high | Read, Grep, Glob, Bash, WebFetch | refuting ONE claim ("it is fixed", "tests pass") with a fresh run |
| `implementer` | opus / high | full default set, `permissionMode: acceptEdits` | building / fixing one disjoint slice from a brief |
| `scout` | haiku / low | Read, Grep, Glob | cheap recon: which files matter, so the brief can be written |

`reviewer` and `verifier` carry **no** `Edit`, `Write`, `MultiEdit` or `NotebookEdit`: the `tools:`
frontmatter is a hard allowlist, and `disallowedTools:` repeats the ban as a second lock. Their shell
access is still real (they must be able to run the test suite), so the hub's `reviewer_guard`
PreToolUse hook denies mutating commands - redirects, `rm`/`mv`/`cp`, `git add|commit|push|...`,
installs - while letting test runners through, and it looks past chaining (`pytest && rm -rf build`),
newlines and a nested shell (`sh -c "rm -rf build"`). Allowlist + denylist + hook: three layers, because a
reviewer that "helpfully" fixes what it found has destroyed the independence that made it useful.

The hook is the SECOND layer, not the only one: it is a regex over a shell string, so an interpreter
one-liner that writes through its own runtime (`python -c "...shutil.rmtree..."`) is not recognized. The
`tools:` allowlist is what actually makes these agents read-only; see `docs\ENFORCEMENT.md` for the limit.

## How the main agent uses them

**Agent tool** - one-off delegation:

```
Agent(subagent_type: 'reviewer', prompt: '<the spec/plan + the file scope + check every gate>')
```

**Workflow tool** - a wave; pass `agentType` in the options and the agent file supplies the model,
effort and tool allowlist (do not re-specify `model:` per call, and never `model: 'fable'` - Fable is
for orchestration and spec writing, not for agent work):

```js
phase('Build')                     // named agents resolve from .claude/agents/ in cwd or ~/.claude/agents/
const built = await parallel(AREAS.map(a => () =>
  agent(`${BRIEF}\nOWNERSHIP: ${a.files}\nGATES: ${a.gates}`, { label: a.name, agentType: 'implementer' })))
phase('Loop')
let round = 0, review = null
while (round < 3) {
  review = await agent(`${BRIEF}\nSCOPE: ${FILES}. Check every gate with evidence you generate yourself.`,
    { label: 'review-r' + round, agentType: 'reviewer', schema: REVIEW_SCHEMA })   // read-only by frontmatter
  const blocking = (review.findings || []).filter(f => f.severity !== 'P3')
  if (!blocking.length) break
  await parallel(byArea(blocking).map(g => () => agent(`${BRIEF}\nCLOSE THESE, then re-run the check:\n${g.text}`,
    { label: 'fix-' + g.area, agentType: 'implementer' })))
  round++
}
return await agent(`CLAIM: "every gate in the plan holds on this tree". Refute it.`,
  { agentType: 'verifier', schema: VERIFY_SCHEMA })
```

## The wave shape

1. **Brief** (main agent, or `scout` first if the file map is unknown). Self-contained: what to read,
   in what order; the ownership set per agent; the gates; what to return.
2. **Implement** - `implementer` per slice, **disjoint file ownership**, in parallel. A worktree is
   only needed when several agents must mutate the SAME tree and a human is running the app from it;
   otherwise disjoint ownership in one checkout is enough.
3. **Review** - `reviewer` with fresh context, against the spec, not against the diff's own story.
4. **Fix** - `implementer` again, one per finding group, ownership still disjoint.
5. **Verify** - `verifier` on the wave's headline claim, then the project's full check, green.

Loop 3-4 at most a few rounds; if findings keep reappearing, the brief was wrong, not the agents.

## Extending / editing an agent

Edit `templates\agents\<name>.md`, mirror it into `.claude\agents\`, run `tools\selftest.ps1`
(section `agents` asserts the frontmatter, the read-only allowlists and the scaffold). Keep the
bodies **generic and personal-data-free** - this is the public engine; project specifics belong in the
brief you hand the agent, not in the role definition.
