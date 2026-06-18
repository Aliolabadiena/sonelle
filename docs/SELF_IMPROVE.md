# SELF-IMPROVE — getting better after every task, from memory

sonelle improves by closing a loop through `memory/`: every task that teaches something
writes it down; every new task recalls it first. Over time the same mistakes stop
recurring and the assistant acts more like it already knows the project.

## The loop
- **Before a task — RECALL.** Skim `memory/MEMORY.md` (the index) and open any topic file
  relevant to what you're about to do. Treat memory as point-in-time: verify file/line
  claims against current code before relying on them.
- **Do the task.**
- **After a task — REFLECT + CAPTURE.** Ask: what broke? what was non-obvious? what did the
  user correct or insist on? what dead-end wasted time? Write each as a lesson:
  `tools\log_lesson.ps1 -Slug <slug> -Type <gotcha|feedback|project|reference> -Desc "<one line>" -Body "<...>" -Why "<...>" -How "<...>"`
  It creates `memory\<slug>.md` and adds an index line to `memory\MEMORY.md`.

## What's worth saving
- **gotcha** — a non-obvious technical trap + how to avoid it.
- **feedback** — guidance the user gave (a correction or a confirmed approach) + the why.
- **project** — durable project state/goals not derivable from the code or git history.
- **reference** — a pointer to an external resource (URL, dashboard, ticket).

Don't save what the repo already records (code structure, past fixes, git history) or what
only mattered to one conversation.

## Keep the index lean
`MEMORY.md` is loaded every session — one short line per memory (`- [Title](file.md) - hook`).
Put detail in the topic file, not the index. If the index gets large, collapse long lines
to pointers and merge duplicates.

## Why this is the most important superpower
Scaffolding and healing make a single task go well. Self-improve makes the NEXT task go
better — the system compounds instead of relearning the same lessons each session.
