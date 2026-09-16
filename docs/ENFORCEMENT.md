# ENFORCEMENT - the rules that are not prose any more (v1.47)

A rule written in `CLAUDE.md` is a wish: the model reads it, weighs it against everything else in the
context, and sometimes ignores it. A rule written as a **PreToolUse hook** is a wall: the tool call does
not happen, whatever the model decided. v1.47 turns the handful of rules that were learned the hard way -
the ones that had to be re-stated after a session broke them - into hooks a hub installs into its
`.claude\`.

Prose still does the teaching. Hooks do the stopping.

## Install

```powershell
tools\install_hub.ps1 -Hub <your hub folder>                     # install / refresh (idempotent)
tools\install_hub.ps1 -Hub <hub> -Canary "Name," -Owner "Name"   # + the optional per-hub settings
tools\install_hub.ps1 -Hub <hub> -Uninstall                      # remove exactly what was installed
```

What lands in `<hub>\.claude\`:

| path | what | written by |
|---|---|---|
| `hooks\*.ps1` | the five guards below | `templates\hub\hooks\` |
| `settings.json` | the hook registrations, **merged** - your `permissions` and any other hooks are kept | `templates\hub\settings.json` |
| `commands\prune.md` | the `/prune` slash command, when the engine ships it (`<engine>` / `<hub>` filled in at copy time) | `templates\hub\commands\` |
| `agents\*.md` | the review-only subagents, when the engine ships them | `templates\agents\` |
| `sonelle.install.json` | the manifest `-Uninstall` reads back | the installer |
| `sonelle.hub.json` | **your** settings: `canary`, `owner` (never overwritten wholesale) | you / `-Canary` / `-Owner` |

The installer refuses to treat the engine folder as a hub, backs up any file it would overwrite to
`*.pre-sonelle.bak`, and strips-then-re-adds its own hook entries, so installing twice changes nothing.
"Its own" means a command pointing at `.claude\hooks\<one of the five names>`: a hook of YOURS whose name
merely contains one of ours (`.claude\hooks\my_stop_guard.ps1`), or the same name under another directory,
is left where it is.

`sonelle.hub.json` is the only place a hub's personal details live:

```json
{ "canary": "Name,", "owner": "Name" }
```

- `canary` - every reply must start with this word (the context-loss check). Absent or empty = check off.
- `owner` - how a block message names you ("Wait for <owner>"). Absent = "the user".

## The five hooks

Each hook lives at `<hub>\.claude\hooks\<name>.ps1` and resolves the hub as **two levels up from itself**
(`$env:SONELLE_HUB` overrides it, which is how selftest runs them against a throwaway hub). Every one of
them **fails OPEN**: an unreadable payload, a changed transcript format, a missing state file - exit 0,
allow the call. A guard that breaks a working session is worse than the rule it enforces.

### 1. `prompt_router.ps1` - UserPromptSubmit (never blocks)

Reads the prompt, records a per-session decision in `%TEMP%\sonelle\mode_<session_id>.json`, and injects a
few lines of context. Matching happens on a diacritic-flattened copy of the text, so accented and
unaccented spellings behave the same.

- **HOLD**: `palauk` / `sustok` / `stok` / `stop`, **addressed to the session** - the word opens the
  message (after an optional `Name,` or `short:` prefix) or stands alone on its own line -> writes
  `<hub>\_HOLD` (timestamp + prompt excerpt) and says so. It is deliberately not "the word appears
  somewhere": `stop` is an ordinary word ("where do you put the stop loss", "the tests stop at section 2"),
  and an accidental HOLD freezes every session on that hub. A release word (`ok`, `gerai`, `tesk`,
  `daryk`, `start`, `go`, `pirmyn`, `continue`, `tvarkyk`) opening a later prompt - a lead-in clause like
  `ne, tesk toliau` counts - deletes it, and the HOLD message says so.
- **Mode**: `mini` anywhere -> MINI. A question (ends in `?`, or opens with `ar/kiek/kas/kodel/kaip/kur/
  kada/koks/kokia/kuris/why/what/how/is/are/does/do/can`) -> QUESTION. A short remark with no `<short>:`
  grammar and no task verb -> MINI. Everything else -> DELEGATE.
- **Fable allowance**: `fable ok` in a prompt sets `fable_ok` for the session.
- **Dispatch**: `[address,] <short>: ...` looks the shortcode up in `<hub>\PROJECTS.md` and injects the
  row's "state sources" column - or, when the shortcode is unknown and is not one of the non-project words
  (`sonelle`, `mini`, `general`, `http`, `https`, `note`, `nb`, `ps`, `todo` - edit the list in the script),
  a warning not to start work on a project that does not exist.

### 2. `hold_guard.ps1` - PreToolUse (matcher `.*`)

The matcher is `.*` **on purpose**: the allowlist lives inside the hook, so a tool nobody listed - an MCP
`apply_migration`, a scheduler, a message send - cannot walk through a HOLD just because its name was not
in a matcher string. The cost is one short PowerShell process per tool call (the hook's first act is a
single `Test-Path` for `_HOLD`, then exit 0); if that ever matters more than the coverage, narrow the
matcher in `<hub>\.claude\settings.json` - the hook behaves the same either way.

While `<hub>\_HOLD` exists, what stays allowed is orientation:

- the read-only tools (`Read`, `NotebookRead`, `Glob`, `Grep`, `LS`, `TodoRead`/`TodoWrite`, `WebSearch`,
  `WebFetch`, `ExitPlanMode`, the MCP resource readers), and MCP calls whose name is read-shaped
  (`...read/list/get/search/query/describe/fetch/status/context/view/inspect...`);
- shell commands in which **every chained command** is read-only (`git status|log|diff|show|branch`, `ls`,
  `dir`, `cat`, `head`, `tail`, `wc`, `grep`, `rg`, `find`, `type`, `Get-ChildItem`, `Get-Content`,
  `Select-String`, `Test-Path`, `Get-Item`, `echo`, `pwd`, `Write-Output`, `python -c "print`) with no
  redirection, no `find -delete`/`-exec`, and no mutating verb hidden in a nested shell or a command
  substitution (`echo "$(rm -rf x)"`) - while grepping FOR such a verb (`grep -rn "Remove-Item" .`) stays
  allowed, because orientation is the whole point of what a HOLD leaves open.
  Chaining is the trap this is built around: `git status && git push origin main` is not a read-only
  command, so the allowlist is applied to **every** segment (`;`, `&`, `&&`, `|`, `||`, newline), never
  just the first;
- editing the `_HOLD` marker itself (exactly `<hub>\_HOLD`, not any file whose name ends in `_HOLD`).

Everything else - edits, `Agent`, `Workflow`, `Task`, `SlashCommand`, `Skill`, unknown tools - is denied.

"palauk" means a full stop, not "finish what you started".

### 3. `main_agent_guard.ps1` - PreToolUse (`Edit|Write|MultiEdit|NotebookEdit|Bash|PowerShell|Agent|Workflow`)

Only ever judges the **main** agent. "Main" is `agent_id` empty/absent (the documented contract); an
`agent_type` on its own excuses the call only when it names a subagent ROLE, so that if Claude Code ever
starts putting a type like `main` on main-agent events, the rules cannot silently switch themselves off.

**Main-vs-subagent detection uses two independent signals**, because `agent_id`/`agent_type` on subagent
calls is still an assumption (see [HOOK_PAYLOADS.md](HOOK_PAYLOADS.md)) and getting it wrong in that
direction breaks delegation entirely - DELEGATE mode would deny the main agent's edit AND the edit by the
subagent it delegated to, leaving no one able to work. The second signal is `transcript_path`, which IS
verified present on every event: a subagent's transcript lives under a `subagents` directory and/or is named
`agent-<hex>.jsonl`, the main agent's is `<uuid>.jsonl` directly in the project folder. A path matching
`[\\/]subagents[\\/]` or an `agent-<6+ hex>.jsonl` leaf is treated as a subagent and is never denied by the
delegate rule; a missing, empty or non-string value simply falls back to the `agent_id` rule (fail-open, as
everywhere else). The excuse is scoped to the delegate rule only - model tiering below still judges every
call, subagent or not.

- **Delegate by default.** In DELEGATE and QUESTION mode the main agent may not edit code: it writes a brief
  and hands the work to a subagent. That includes writing code **through a shell** (`>`/`>>`, `tee`,
  `sed -i`, `Set-Content`/`Add-Content`/`Out-File`/`New-Item`) - denying `Edit` while a heredoc redirect
  into a source file walks through is exactly the loophole a model takes once an Edit comes back denied.
  The write verb is looked for through the same disguises `reviewer_guard` handles below: a nested shell
  (`sh -c "Set-Content src\a.gd x"`) and a launcher prefix (`sudo tee src\a.gd`, `xargs Set-Content ...`).
  Exempt, because they are orchestration output rather than code: `*_TODO.txt`, `*_run_STATUS.md`,
  anything under `memory\`, `CLAUDE.md`, `PROJECTS.md`, `_*_SPEC|PLAN|BRIEF|HANDOFF*.md`, `_*_waves\`,
  `.claude\`, a `scratchpad\` **directory** (not a filename that merely contains the word), `%TEMP%`,
  `/dev/null`, and any `.md` under the hub root. MINI mode - or no recorded mode at all - allows
  everything.
- **Model tiering.** An `Agent` call with `model: fable`, or a `Workflow` script (inline `script` or a
  `scriptPath` read from disk) that sets `model: 'fable'`, is denied unless the session heard `fable ok`.

### 4. `reviewer_guard.ps1` - PreToolUse (`Bash|PowerShell|Write|Edit|MultiEdit|NotebookEdit`)

Applies only when `agent_type` (or `agentType` / `subagent_type`) is `reviewer` or `verifier`. Those
agents already lack Edit/Write in their frontmatter allowlist; this closes the shell door:
`rm|mv|cp|del|rmdir|mkdir|touch|sed -i`, `git add|commit|push|checkout|switch|reset|rebase|merge|stash|
clean|restore`, `npm i|install|ci|run build`, `pip install`, `Set-Content|Out-File|Add-Content|
Remove-Item|Move-Item|Copy-Item|Rename-Item|New-Item`, `find ... -delete|-exec`, and any real `>`, `>>`
or `| tee` are denied.

The deny patterns are **anchored** to a command boundary (start of the string, or after `;` `&` `|` or a
newline). That is what lets a review quote a verb as evidence without being denied for it - and it is also
what four disguises exploit, so each is handled on purpose:

- **chaining** - the deny patterns are evaluated for every command in the chain, and a test-runner word no
  longer exempts the line: `rm -rf build && pytest -q` is denied, `pytest -q` is not.
- **newlines** - a multi-line command is one tool call, so a newline counts as a command separator.
- **nested shells** - `sh -c "rm -rf build"`, `powershell -Command "Remove-Item x"`, `echo "$(rm -rf x)"`,
  backticks, `<<<`: when a shell or interpreter is actually being invoked (or a substitution is used), the
  patterns are also matched against a copy in which quotes, parens and the `-c`-style flag are separators.
- **launcher prefixes** - `sudo rm -rf x`, `env rm x`, `time rm x`, `find . | xargs rm -rf build`,
  `git ls-files | xargs sed -i ...`: a prefix word (`sudo`, `doas`, `env`, `nohup`, `nice`, `ionice`,
  `stdbuf`, `setsid`, `timeout`, `time`, `command`, `builtin`, `exec`, `xargs`, `wsl`) keeps the real verb
  off the start of its segment, so those words become separators too.

Test runners (`npm test`, `pytest`, `go test`, `dotnet test`, a `*selftest*` PowerShell file) match none of
the deny patterns and so stay allowed - a reviewer that cannot run the test it is judging is useless - as
long as the test run IS the command. Redirects to `/dev/null` / `NUL` / `$null` are not side effects, and
`->`, `=>`, `>=` and `2>&1` are not redirects, so evidence commands like `grep -n "a->b" src/x.c` work.
Quote flattening happens only when a shell/interpreter really is invoked, so the commands a review lives on
- `grep -rn "Remove-Item" .`, `rg "New-Item" -n tools/` - are allowed rather than denied for the quote.

**Known limit** (stated rather than pretended away): this is a regex over a shell string. An interpreter
one-liner that writes through its own runtime - `python -c "...shutil.rmtree..."`, `node -e
"...writeFileSync..."` - is not recognized, and neither is a verb behind an unlisted launcher (`ssh host rm
-rf x` mutates the remote host, not this tree). The frontmatter `tools:` allowlist and `disallowedTools:`
are the primary defence; this hook is the second layer, not the only one.

### 5. `stop_guard.ps1` - Stop

Reads the transcript (fail-open at every step; `stop_hook_active` short-circuits the re-entry so it cannot
loop) and looks at the last assistant message:

- no `text` block at all (the turn ended on tool calls) -> **block**: end the turn with text.
- `canary` configured and the final text does not start with it -> **block**.
- prune stamp (`<hub>\.claude\sonelle_prune_stamp`) missing or older than 30 days -> a nudge to run
  `/prune`, once per session. Never blocks. It goes out as hook JSON (`{"systemMessage": ...}`): a Stop
  hook's plain stdout is only surfaced in transcript mode, so a bare text line would consume the
  once-per-session marker while reaching nobody.

## When a guard is wrong

- **One call**: rephrase or say `mini` - MINI mode turns the delegate rule off for the session.
- **One session**: `$env:SONELLE_HUB` is only for tests; to disable a hook for real, remove its entry from
  `<hub>\.claude\settings.json` (or run `-Uninstall`) and restart the session - hooks are read at startup.
- **Permanently**: change the hook in `templates\hub\hooks\`, extend `tools\selftest.d\hooks.ps1` with the
  case that was wrong, and re-run `install_hub.ps1`. A guard without a test is how the next regression gets
  in.

## Tests

`tools\selftest.d\hooks.ps1` (dot-sourced by `tools\selftest.ps1`, or run on its own) feeds each hook
synthetic payloads on stdin as raw UTF-8 - HOLD set/release including the prompts that must NOT set one,
chained and nested-shell commands under a HOLD, the tool-coverage allowlist, delegate deny vs state-file
allow, shell writes, the scratchpad path rule, caller detection (`agent_id` / `agentId` / a role in
`agent_type` / a subagent-shaped `transcript_path`, including the malformed ones that must fall back),
MINI/QUESTION, fable deny + allowance, Workflow script and scriptPath, the reviewer's
chained / multi-line / nested-shell / `find -delete` denials and its read-only evidence commands,
stop-guard block on a tool-only turn and on a missing canary, pass on a good turn and on a garbage
transcript - plus install/merge/idempotency/uninstall for `install_hub.ps1` (including a foreign hook whose
filename merely CONTAINS one of ours), a golden set-equality check on `templates\hub\**` and
`templates\agents\**`, and a behavioral fail-open pass: every hook is fed empty, junk and partial stdin and
must exit 0.

The suite is safe to run twice at once - every temp path it uses and every session id it invents carries
the PID - which matters because the wave pattern runs two reviewers in parallel and both of them run it.

What the payloads are actually shaped like, and which parts are still assumptions, is in
[HOOK_PAYLOADS.md](HOOK_PAYLOADS.md). Re-run `tools\hook_probe.ps1` after a Claude Code upgrade if a guard
starts behaving oddly - a renamed field would make a guard fail open and quietly stop enforcing.
