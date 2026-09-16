# Hook payloads - what Claude Code actually sends (T0 capture)

Everything the enforcement hooks (`templates/hub/hooks/*.ps1`) read from stdin is listed here, split
into **VERIFIED** (captured on this machine with `tools/hook_probe.ps1`) and **UNVERIFIED - assumed**
(from the docs; the hooks tolerate both shapes and fail OPEN when a field is missing).

Capture method: a throwaway folder with `.claude/settings.json` registering `tools/hook_probe.ps1` on
`UserPromptSubmit`, `PreToolUse` (matcher `*`), `Stop` and `SubagentStop`, then one cheap
`claude -p "..." --model haiku` run in that folder. Paths and prompt text below are placeholders.

- Claude Code version at capture time: **2.1.205**, Windows 10, PowerShell 5.1.
- Capture date: 2026-09-16.

## VERIFIED - UserPromptSubmit

Real line (values replaced with placeholders, key names and nesting verbatim):

```json
{
  "session_id": "<uuid>",
  "transcript_path": "<home>\\.claude\\projects\\<encoded-cwd>\\<uuid>.jsonl",
  "cwd": "<project dir>",
  "prompt_id": "<uuid>",
  "permission_mode": "acceptEdits",
  "hook_event_name": "UserPromptSubmit",
  "prompt": "<the user's message, verbatim>"
}
```

Facts the hooks rely on:
- the prompt field is **`prompt`** (not `user_prompt` / `message`) - `prompt_router.ps1` still tries the
  other two names, because one field name is a thin thing to bet a router on.
- `session_id` is present -> the per-session state file `%TEMP%\sonelle\mode_<session_id>.json` is keyed on it.
- there is **no `agent_id` / `agent_type`** on a main-agent event. That is the signal the guards use to tell
  the main agent from a subagent, and it is the one assumption that would silently weaken H3/H4 if it changed
  (see "risk" below).
- `transcript_path` is absolute and uses Windows separators.
- payload encoding is UTF-8, so every hook reads stdin through `StreamReader(..., UTF8)` - PS 5.1's
  `[Console]::In` uses the console code page and mangles non-ASCII prompts (Lithuanian, in this hub's case).

## VERIFIED - tool_input key names (from transcript `tool_use` blocks)

The `tool_input` object a PreToolUse hook receives is the same object the transcript records as the
tool_use block's `input`. Counted over recent local transcripts (key names only, no content):

| tool | input keys seen |
|---|---|
| `Agent` | `description`, `prompt`, `model`, `subagent_type` (only on some calls), `run_in_background` |
| `Workflow` | `scriptPath` (common), `script` (inline, rarer), `args` |
| `Bash` / `PowerShell` | `command`, `description`, `timeout`, `run_in_background` |
| `Write` | `file_path`, `content` |
| `Edit` | `file_path`, `old_string`, `new_string`, `replace_all` |

Consequences: `main_agent_guard.ps1` reads `tool_input.model` for the Fable-tiering check and accepts BOTH
`tool_input.script` and `tool_input.scriptPath` for Workflow; `hold_guard`/`reviewer_guard` read
`tool_input.command`; the path guards read `file_path` (and fall back to `notebook_path`).

## VERIFIED - transcript JSONL shape (what `stop_guard.ps1` parses)

Measured on local transcripts:
- one JSON object per line; the **last line is often NOT an assistant line** (`system`, `attachment`,
  `queue-operation`, `file-history-snapshot` and others appear after it) - so the guard scans backwards for
  the last line whose `message.role == "assistant"` instead of trusting the tail.
- an assistant line looks like `{ "type": "assistant", "uuid", "sessionId", "cwd", "isSidechain",
  "timestamp", "message": { "role": "assistant", "content": [ ... ] } }`.
- `message.content` is an **array of blocks**; block types observed: `thinking`, `text`, `tool_use`
  (a text block is `{ "type": "text", "text": "..." }`). A turn that ends in tool calls has NO `text` block -
  that is exactly the "end the turn with text" rule H5 enforces.
- user lines carry `message.content` as either a string or an array -> never assume one.

## UNVERIFIED - assumed (docs only; hooks tolerate both shapes)

The probe could not complete a full session on this machine: the child `claude` CLI reported
`Not logged in` (the desktop app holds the credentials; no login was attempted). So these were NOT captured:

1. **PreToolUse envelope**: assumed `{ session_id, transcript_path, cwd, permission_mode, hook_event_name,
   tool_name, tool_input }`. The `tool_input` key names above ARE verified; the envelope is not.
2. **`agent_id` / `agent_type` on subagent calls**: assumed present when the call comes from a subagent and
   absent/empty for the main agent. `main_agent_guard.ps1` treats "no `agent_id`" as main, and
   `reviewer_guard.ps1` keys off `agent_type` matching `^(reviewer|verifier)$`.
   **Risk, both directions:** if `agent_id` is absent for subagents too, H3 would also deny subagent edits
   (loud, caught immediately). If `agent_type` is absent or spelled differently, H4 silently stops enforcing
   review-only - a quiet failure. Both hooks read `agent_id`/`agentId` and `agent_type`/`agentType`/
   `subagent_type` before deciding.
   **Second signal (`transcript_path`), for the first direction:** because "H3 denies subagent edits" would
   break delegation outright (DELEGATE mode denies the main agent AND, without a working caller signal, the
   subagent it just handed the work to), `main_agent_guard.ps1` also accepts a subagent-shaped
   `transcript_path` as an excuse for the delegate rule. `transcript_path` is VERIFIED present on every
   event, and Claude Code writes a subagent's transcript under a `subagents` directory and/or as
   `agent-<hex>.jsonl` (observed locally: `<...>\subagents\workflows\wf_<id>\agent-<16 hex>.jsonl` and
   `<...>\subagents\agent-<hex>.jsonl`), while the main agent's is `<uuid>.jsonl` directly in the project
   folder. The match is `(?i)[\\/]subagents[\\/]` OR a leaf matching `(?i)^agent-[0-9a-f]{6,}\.jsonl$`; a
   missing, empty or non-string value just falls back to the `agent_id`/`agent_type` rule. The naming is
   itself an observation rather than a contract, which is why it is a SECOND signal and not a replacement -
   two independent signals have to both change before delegation breaks. It is deliberately scoped to the
   delegate rule, so the Fable-tiering check is unaffected.
3. **Stop payload**: assumed `{ session_id, transcript_path, hook_event_name, stop_hook_active }`. The
   loop-guard depends on `stop_hook_active` being true on the re-entry; if it is missing, the guard would
   still not loop forever, because a blocked turn that then ends with text passes the check.
4. **Whether hooks MERGE across settings levels** (`~/.claude/settings.json` vs `<hub>/.claude/settings.json`):
   untested. The design assumes hub-level `.claude/settings.json` alone is enough, which is what
   `tools/install_hub.ps1` writes.
5. **`hookSpecificOutput.additionalContext` on UserPromptSubmit**: documented, not observed here.
   `prompt_router.ps1` prints the JSON form; if the shape were wrong, Claude would see the raw JSON as
   injected context - noisy, never fatal.

## Re-running the probe

```powershell
# 1. a throwaway folder with .claude\settings.json pointing every event at the probe
#    (use FORWARD slashes in the command string - a raw "\" in JSON is an invalid escape and the
#     whole settings file is then ignored; this bit us during T0)
# 2. one cheap session in that folder
claude -p "Use the Agent tool with model haiku to read README.md, then answer OK" --model haiku
# 3. read the capture
Get-Content $env:TEMP\sonelle\probe.jsonl
```

Each probe line is `{"probe_event":"<event>","ts":"<iso>","payload":<raw stdin JSON>}`. When the payload is
not JSON it is stored as a string, so the file always parses. Delete the capture when done - it contains
whatever the session said.
