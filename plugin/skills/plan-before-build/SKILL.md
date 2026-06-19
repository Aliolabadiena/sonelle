---
name: plan-before-build
description: Turn a large, vague, or multi-file request into an agreed design and a concrete step-by-step plan before writing code. Use when the task is ambiguous, spans several files, or is a new feature, redesign, or refactor. Do NOT use for a small, clear, single-file change - just do that directly.
---

# Plan before you build

For anything big or unclear, design first. This is how you scale effort up appropriately instead
of diving into code and discovering the shape halfway through.

## 1. Understand (brainstorm the design)
- Pin the purpose, the constraints, and what success looks like.
- Ask the user ONE question at a time, multiple-choice when you can, until the goal is clear.
- Propose 2-3 competing approaches with trade-offs before settling on one.
- Get agreement on the approach BEFORE writing implementation code (hard gate).

## 2. Write the plan
- Header: the goal, the chosen approach, the files created/modified, global constraints.
- Break the work into small steps, each one action: write test -> see it fail -> implement ->
  see it pass -> move on. Size each step so it can be reviewed or dropped on its own.
- No placeholders: every step names the real change and the expected result, never
  "add error handling here".
- Assume the implementer knows the craft but NOT this codebase - be concrete.

## 3. Keep state where it belongs
Record the plan and progress in the project's own TODO / ledger (the end-of-task ritual), not a
parallel notes tree, so it rides the normal workflow.
