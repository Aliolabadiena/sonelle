<#
  main_agent_guard.ps1 - PreToolUse hook.
  Matcher: Edit|Write|MultiEdit|NotebookEdit|Bash|PowerShell|Agent|Workflow.

  Two rules, both about the MAIN agent only (a call carrying agent_id/agent_type - or a subagent-shaped
  transcript_path - comes from a subagent and is never denied under rule 1):

   1. DELEGATE-by-default. In DELEGATE (and in QUESTION, where the answer comes first) the main agent does
      not edit CODE - it writes a brief and hands the work to a subagent. That covers writing through a
      SHELL too (a redirect, tee, sed -i, Set-Content/Out-File/Add-Content/New-Item), which is otherwise
      the obvious way around a denied Edit. Orchestration output stays exempt:
      TODO files, ledgers, memory, CLAUDE.md / PROJECTS.md, _*_SPEC/PLAN/BRIEF/HANDOFF*.md, _*_waves\,
      .claude\, scratchpads, and any .md under the hub root. MINI (or no mode recorded) allows everything.
   2. Model tiering. A Fable subagent (Agent tool with model "fable", or a Workflow script that sets
      model: 'fable') is denied unless the session was given the allowance ("fable ok" in a prompt).

  Mode comes from %TEMP%\sonelle\mode_<session_id>.json, written by prompt_router.ps1. No state file means
  no opinion: exit 0. Exit 2 = blocked (stderr goes back to Claude). Fail-OPEN on any parse problem.
#>
$ErrorActionPreference = 'SilentlyContinue'

try { $raw = (New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)).ReadToEnd() } catch { exit 0 }
if (-not $raw) { exit 0 }
try { $j = $raw | ConvertFrom-Json } catch { exit 0 }

$tool = [string]$j.tool_name
$ti   = $j.tool_input

# caller: the main agent carries no agent id (per the spec/T0; see docs\HOOK_PAYLOADS.md). `agent_type`
# is a secondary signal only, and only when it names a SUBAGENT role - if Claude Code ever starts putting
# a type on main-agent events ("main"/"default"/...), treating any type as "not the main agent" would
# silently switch both rules off with no visible symptom.
$agentId = [string]$j.agent_id
if (-not $agentId) { $agentId = [string]$j.agentId }
$agentTy = [string]$j.agent_type
if (-not $agentTy) { $agentTy = [string]$j.agentType }
if (-not $agentTy) { $agentTy = [string]$j.subagent_type }
if ($agentId.Trim()) { exit 0 }
if ($agentTy.Trim() -and ($agentTy.Trim() -notmatch '(?i)^(main|primary|root|default|general|user|none)$')) { exit 0 }

# SECOND, independent subagent signal: transcript_path (VERIFIED present on every event, unlike
# agent_id/agent_type, which are still an assumption for subagent calls - docs\HOOK_PAYLOADS.md). A
# subagent's transcript is written under a `subagents` directory and/or named `agent-<hex>.jsonl`; the main
# agent's is `<uuid>.jsonl` sitting directly in the project folder. If agent_id turns out NOT to be sent to
# subagents, this is what keeps DELEGATE mode from denying the very subagent it delegated to (which would
# break delegation outright). It is an extra EXCUSE for rule 1 only - deliberately not an early exit 0, so
# the Fable-tiering check (rule 2) keeps judging every call exactly as before.
$tpath = [string]$j.transcript_path
if (-not $tpath) { $tpath = [string]$j.transcriptPath }
$subByTranscript = $false
if ($tpath.Trim()) {
  if (($tpath -match '(?i)[\\/]subagents[\\/]') -or ($tpath -match '(?i)(^|[\\/])agent-[0-9a-f]{6,}\.jsonl$')) { $subByTranscript = $true }
}

$sid = [string]$j.session_id
if (-not $sid) { $sid = [string]$j.sessionId }
if (-not $sid) { $sid = 'nosession' }
$statePath = Join-Path (Join-Path $env:TEMP 'sonelle') ('mode_' + ($sid -replace '[^A-Za-z0-9_\-]', '_') + '.json')

$mode    = ''
$fableOk = $false
if (Test-Path $statePath) {
  try {
    $st = Get-Content $statePath -Raw | ConvertFrom-Json
    $mode = [string]$st.mode
    if ($st.fable_ok) { $fableOk = $true }
  } catch { }
}

$hub = $env:SONELLE_HUB
if (-not $hub) { $hub = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }
# how to name the hub owner in a message: <hub>\.claude\sonelle.hub.json {"owner": "..."} (optional)
$owner = 'the user'
try {
  $cfgP = Join-Path $hub '.claude\sonelle.hub.json'
  if (Test-Path $cfgP) { $o = (Get-Content $cfgP -Raw | ConvertFrom-Json).owner; if ($o) { $owner = [string]$o } }
} catch { }

function Deny([string]$msg) {
  [Console]::Error.WriteLine('sonelle: ' + $msg)
  exit 2
}
$fableMsg = 'Model tiering: subagents run opus (review/verify effort high). Fable subagent only if ' + $owner + ' says "fable ok".'

# --- 2. model tiering ------------------------------------------------------------------------------
if ($tool -eq 'Agent') {
  if ((-not $fableOk) -and ([string]$ti.model -match '(?i)fable')) { Deny $fableMsg }
  exit 0
}
if ($tool -eq 'Workflow') {
  if (-not $fableOk) {
    $scriptText = [string]$ti.script
    if (-not $scriptText) {
      $sp = [string]$ti.scriptPath
      if ($sp) {
        try {
          if (-not [System.IO.Path]::IsPathRooted($sp)) {
            $base = [string]$j.cwd
            if ($base) { $sp = Join-Path $base $sp }
          }
          if (Test-Path $sp) { $scriptText = Get-Content $sp -Raw }
        } catch { }
      }
    }
    if ($scriptText -match "model\s*:\s*['`"]fable") { Deny $fableMsg }
  }
  exit 0
}

# --- 1. delegate by default ------------------------------------------------------------------------
if ($tool -notmatch '^(Edit|Write|MultiEdit|NotebookEdit|Bash|PowerShell)$') { exit 0 }
if ($mode -ne 'DELEGATE' -and $mode -ne 'QUESTION') { exit 0 }
if ($subByTranscript) { exit 0 }   # a subagent doing the delegated work: this rule is not about it

function Deny-Delegate([string]$what) {
  if ($mode -eq 'QUESTION') {
    Deny ('QUESTION mode: answer first, do not act. ' + $owner + ' asked something - reply, and ' + $what + ' only after "daryk/ok". (State files and docs are exempt.)')
  }
  Deny ('DELEGATE mode: the main agent does not edit code. Hand it to a subagent (Agent, model opus). Exempt: state files. If this is truly a one-liner, ' + $owner + ' says "mini".')
}

# writing code through a SHELL is the same rule: denying Edit/Write while `cat > src\a.gd <<EOF` walks
# through is the loophole a model takes the moment an Edit comes back denied.
if ($tool -match '^(Bash|PowerShell)$') {
  $cmd = [string]$ti.command
  if (-not $cmd) { exit 0 }
  $noNull   = $cmd -replace '(?i)\d?>>?\s*(/dev/null|nul|\$null)', ' '
  $writeVerb = '(?m)(^|[;&|\r\n]\s*)(tee|sed\s+-i|Set-Content|Add-Content|Out-File|New-Item)\b'
  $redirect  = '(^|[^-=<>!])>{1,2}\s*[^&\s=]'
  # $writeVerb is anchored to a command boundary, so the same two disguises reviewer_guard handles apply
  # here: a nested shell (`sh -c "Set-Content src\a.gd x"`) and a launcher prefix (`sudo tee src\a.gd`,
  # `xargs Set-Content ...`). Normalize a copy; the quote flattening only happens when a shell really is
  # invoked, so reading code that MENTIONS a verb (`grep -rn "Set-Content" tools/`) stays allowed.
  $isShellCall = $cmd -match '(?i)(^|[\s;&|(])(sh|bash|zsh|dash|ksh|cmd|powershell|pwsh|python3?|perl|ruby|node|deno|eval)(\.exe)?\b'
  $norm = $cmd
  if ($isShellCall -or ($cmd -match '\x24\(|[\x60]|<<<')) { $norm = $norm -replace '[\x22\x27\x60()\x24]', ';' }
  $norm = $norm -replace '(?i)\b(sudo|doas|env|nohup|nice|ionice|stdbuf|setsid|timeout|time|command|builtin|exec|xargs|wsl)\b', ';'
  if ($isShellCall) { $norm = $norm -replace '(?i)(^|[\s;])(-{1,2}[a-z]*c|/c|/k)([\s;]|$)', '; ' }
  if (($cmd -notmatch $writeVerb) -and ($norm -notmatch $writeVerb) -and ($noNull -notmatch $redirect)) { exit 0 }
  # orchestration output + throwaway paths are exempt, exactly as they are for Edit/Write
  $exemptCmd = @(
    '_TODO\.txt', '_run_STATUS\.md', '[\\/]memory[\\/]', 'CLAUDE\.md', 'PROJECTS\.md',
    '[\\/]_[^\\/\s]*_(SPEC|PLAN|BRIEF|HANDOFF)[^\\/\s]*\.md', '[\\/]_[^\\/\s]*_waves[\\/]',
    '[\\/]\.claude[\\/]', '[\\/]scratchpad', '(?i)[\\/]te?mp[\\/]', '(?i)%TEMP%', '(?i)\$env:TEMP'
  )
  foreach ($rx in $exemptCmd) { if ($cmd -match $rx) { exit 0 } }
  Deny-Delegate 'write files from a shell'
}

$path = [string]$ti.file_path
if (-not $path) { $path = [string]$ti.notebook_path }
if (-not $path) { exit 0 }
$full = $path
try { $full = [System.IO.Path]::GetFullPath($path) } catch { }

$exempt = @(
  '_TODO\.txt$',
  '_run_STATUS\.md$',
  '[\\/]memory[\\/]',
  'CLAUDE\.md$',
  'PROJECTS\.md$',
  '[\\/]_[^\\/]*_(SPEC|PLAN|BRIEF|HANDOFF)[^\\/]*\.md$',
  '[\\/]_[^\\/]*_waves[\\/]',
  '[\\/]\.claude[\\/]',
  '[\\/]scratchpad[\\/]'
)
foreach ($rx in $exempt) { if ($full -match $rx) { exit 0 } }
# docs written at the hub root are orchestration output, not code
if (($full -match '\.md$') -and ($hub) -and ($full.StartsWith($hub, [System.StringComparison]::OrdinalIgnoreCase))) { exit 0 }

Deny-Delegate 'edit'
