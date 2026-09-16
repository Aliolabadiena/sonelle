<#
  hold_guard.ps1 - PreToolUse hook. Matcher: `.*` (every tool; the allowlist lives HERE, not in the
  matcher, so a tool nobody thought of - an MCP write, a scheduler, a message send - cannot walk through
  a HOLD just because its name is not in a list).

  "palauk" means a FULL stop, not "wind down". While <hub>\_HOLD exists (written by prompt_router.ps1)
  this guard denies every edit, agent, workflow and side-effecting tool call. What stays allowed is
  orientation: the read-only tools (Read/Grep/Glob/...), read-shaped MCP calls, shell commands in which
  EVERY chained command is read-only and nothing redirects or mutates, and editing the _HOLD marker.

  Chaining is the trap this guard is built around: `git status && git push` is not a read-only command,
  so the allowlist is applied to every segment (`;`, `&`, `&&`, `|`, `||`, newline), not just the first.

  Exit 2 = blocked (stderr goes back to Claude). Exit 0 = allowed. Fail-OPEN on any parse problem.
  Hub root: two levels up from this script, or $env:SONELLE_HUB for tests.
#>
$ErrorActionPreference = 'SilentlyContinue'

try { $raw = (New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)).ReadToEnd() } catch { exit 0 }
if (-not $raw) { exit 0 }
try { $j = $raw | ConvertFrom-Json } catch { exit 0 }

$hub = $env:SONELLE_HUB
if (-not $hub) { $hub = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }
$holdFile = Join-Path $hub '_HOLD'
if (-not (Test-Path $holdFile)) { exit 0 }

# how to name the hub owner in a message: <hub>\.claude\sonelle.hub.json {"owner": "..."} (optional)
$owner = 'the user'
try {
  $cfgP = Join-Path $hub '.claude\sonelle.hub.json'
  if (Test-Path $cfgP) { $o = (Get-Content $cfgP -Raw | ConvertFrom-Json).owner; if ($o) { $owner = [string]$o } }
} catch { }

$since = ''
$why   = ''
try {
  $hl = @(Get-Content $holdFile -ErrorAction SilentlyContinue)
  if ($hl.Count -ge 1) { $since = [string]$hl[0] }
  if ($hl.Count -ge 2) { $why = [string]$hl[1] }
} catch { }
if ($why.Length -gt 80) { $why = $why.Substring(0, 80) + '...' }

$tool = [string]$j.tool_name
if (-not $tool) { $tool = [string]$j.toolName }
$ti   = $j.tool_input

function Deny([string]$msg) {
  [Console]::Error.WriteLine('sonelle HOLD: ' + $msg)
  exit 2
}
$holdLine = 'HOLD active since ' + $since + ' ("' + $why + '"): no edits/agents/workflows. Zero-cost prep only. Wait for ' + $owner + '. (' + $owner + ' releases it by starting a message with ok/tesk/daryk/start; the marker is ' + $holdFile + '.)'

if (-not $tool) { exit 0 }

# --- tools that only ever READ stay available: orientation is zero-cost ----------------------------
if ($tool -match '(?i)^(Read|NotebookRead|Glob|Grep|LS|TodoRead|TodoWrite|WebSearch|WebFetch|ExitPlanMode|ListMcpResources|ReadMcpResource|ListAgents)$') { exit 0 }

if ($tool -match '^(Edit|Write|MultiEdit|NotebookEdit)$') {
  $path = [string]$ti.file_path
  if (-not $path) { $path = [string]$ti.notebook_path }
  if ($path -match '(^|[\\/])_HOLD$') { exit 0 }        # releasing/annotating the marker itself is fine
  Deny $holdLine
}

if ($tool -match '^(Bash|PowerShell)$') {
  $cmd = [string]$ti.command
  if (-not $cmd) { exit 0 }
  $readOnly = '^\s*(git\s+(status|log|diff|show|branch)|ls|dir|cat|head|tail|wc|grep|rg|find|type|Get-ChildItem|Get-Content|Select-String|Test-Path|Get-Item|echo|pwd|Write-Output|python\s+-c\s+"print)\b'
  # find's own destructive actions carry no verb of their own; a redirect is a write with no verb at all
  $findAct  = '(?i)(^|\s)-(delete|exec|execdir|ok)\b'
  $redirect = '(^|[^-=<>!])>{1,2}\s*[^&\s=]|\|\s*tee\b'
  # every chained command must itself be read-only - `git status && git push` is not
  $segs = @($cmd -split '(?:\r?\n|[;&|])' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  $allRead = ($segs.Count -gt 0)
  foreach ($s in $segs) { if ($s -notmatch $readOnly) { $allRead = $false; break } }
  # belt: when a shell/interpreter is really invoked (or a substitution is used), quotes, parens and $
  # become separators too, so a mutating verb hidden in `sh -c "rm -rf x"` or `echo "$(rm -rf x)"` is
  # still seen. Only THEN - orientation under a HOLD includes grepping for a verb (`grep -rn
  # "Remove-Item" .`), and flattening every quoted string would deny that for quoting it.
  $mutating = '^\s*(rm|mv|cp|del|rmdir|mkdir|touch|sed\s+-i|git\s+(add|commit|push|checkout|switch|reset|rebase|merge|stash|clean|restore)|npm|npx|pip|dotnet|cargo|Set-Content|Add-Content|Out-File|Remove-Item|Move-Item|Copy-Item|Rename-Item|New-Item|Start-Process|Invoke-WebRequest|Invoke-RestMethod|curl|wget)\b'
  $isShellCall = $cmd -match '(?i)(^|[\s;&|(])(sh|bash|zsh|dash|ksh|cmd|powershell|pwsh|python3?|perl|ruby|node|deno|eval)(\.exe)?\b'
  $norm = $cmd
  if ($isShellCall -or ($cmd -match '\x24\(|[\x60]|<<<')) { $norm = $norm -replace '[\x22\x27\x60()\x24]', ';' }
  foreach ($s in @($norm -split '(?:\r?\n|[;&|])')) {
    if ($s.Trim() -match $mutating) { $allRead = $false; break }
  }
  if ($allRead -and ($cmd -notmatch $findAct) -and ($cmd -notmatch $redirect)) { exit 0 }
  Deny ($holdLine + ' (read-only inspection is still allowed: git status/log/diff, ls, cat, grep, Test-Path - every chained command must be read-only, with no redirection)')
}

if ($tool -match '^(Agent|Workflow|Task|SlashCommand|Skill)$') { Deny $holdLine }

# --- anything else (MCP servers, harness tools): read-shaped names pass, the rest is denied ---------
if ($tool -match '(?i)^mcp__.*(read|list|get|search|query|describe|fetch|status|context|view|inspect)') { exit 0 }

Deny ($holdLine + ' Blocked tool: ' + $tool + '.')
