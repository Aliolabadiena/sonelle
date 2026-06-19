# Claude Code transcripts: parse them for token usage + cost (no API key)

Claude Code writes a JSONL transcript per session under
`~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`. The folder name is the session's working
directory with every `:` `\` and `/` turned into `-` (so `C:\Users\me\proj` becomes
`C--Users-me-proj`). Each assistant turn is one JSON line carrying `message.model` and
`message.usage` with `input_tokens`, `output_tokens`, `cache_creation_input_tokens`, and
`cache_read_input_tokens`.

So you can build a cost / usage report by SUMMING those locally - no API key and no network, the
same approach ccusage takes. Multiply tokens by a price table (cache-write counts about 1.25x
input, cache-read about 0.1x input). The numbers are an ESTIMATE (a client-side price table) -
good for budgeting, not billing. sonelle's `tools\cost.ps1` (the `:cost` command) does exactly
this; it reads the real folder by default and honors a `SONELLE_CLAUDE_PROJECTS` env override so a
test can point at a fake transcript tree and stay hermetic.
