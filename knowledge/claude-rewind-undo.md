# Claude Code /rewind - native undo (and its limits)

Claude Code automatically checkpoints your code before each of ITS OWN file edits. Run `/rewind`
(or press Esc twice on an empty prompt) to restore the code, the conversation, or both - a fast
local undo when an edit went the wrong way.

LIMIT (matters on sonelle, which is PowerShell/CLI-heavy): checkpoints only track files changed
through Claude's Write / Edit / NotebookEdit tools. Changes made by BASH/PowerShell commands
(Remove-Item, Move-Item, output redirection, sed -i, git operations) and edits from other
sessions are NOT captured, so `/rewind` will not undo them. For anything driven by a shell
command - and for a real safety net - use git: commit before risky work, branch per experiment.
`/rewind` is a convenience on top of version control, not a replacement for it.
