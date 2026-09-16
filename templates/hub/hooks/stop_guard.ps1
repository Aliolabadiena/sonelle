<#
  stop_guard.ps1 - Stop hook. Checks how the turn ENDED, from the transcript.

   1. A turn must end with TEXT for the hub owner. If the last assistant message has no text block (it
      ended on tool calls / thinking only), block: the session must say something before it stops.
   2. Canary. If <hub>\.claude\sonelle.hub.json has {"canary": "..."} and it is non-empty, the final text
      must start with it (the owner's context-loss canary). Absent file or empty canary = check disabled.
   3. Prune nudge (never blocks): if <hub>\.claude\sonelle_prune_stamp is missing or older than 30 days,
      emit a reminder. Once per session (marker in %TEMP%\sonelle) so it does not nag every turn. A Stop
      hook's plain stdout only shows in transcript mode, so the nudge goes out as hook JSON
      ({"systemMessage": ...}) - otherwise it would be written to a stream nobody reads while the
      once-per-session marker is consumed anyway.

  The transcript JSONL format is INTERNAL to Claude Code and may change without notice, so every step here
  is fail-OPEN: unreadable, unparseable or unrecognizable -> exit 0 silently. `stop_hook_active` short-
  circuits the re-entry, so this can never loop.

  Exit 2 = the turn is not allowed to stop yet (stderr goes back to Claude). Exit 0 = fine.
#>
$ErrorActionPreference = 'SilentlyContinue'

try { $raw = (New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)).ReadToEnd() } catch { exit 0 }
if (-not $raw) { exit 0 }
try { $j = $raw | ConvertFrom-Json } catch { exit 0 }
if ($j.stop_hook_active -eq $true) { exit 0 }

$hub = $env:SONELLE_HUB
if (-not $hub) { $hub = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }
# how to name the hub owner in a message: <hub>\.claude\sonelle.hub.json {"owner": "..."} (optional)
$owner = 'the user'
try {
  $cfgP = Join-Path $hub '.claude\sonelle.hub.json'
  if (Test-Path $cfgP) { $o = (Get-Content $cfgP -Raw | ConvertFrom-Json).owner; if ($o) { $owner = [string]$o } }
} catch { }

# --- 3. prune nudge (computed first so a block can carry it along) ---------------------------------
$nudge = ''
try {
  $sid = [string]$j.session_id
  if (-not $sid) { $sid = [string]$j.sessionId }
  if (-not $sid) { $sid = 'nosession' }
  $stateDir = Join-Path $env:TEMP 'sonelle'
  $marker = Join-Path $stateDir ('nudge_' + ($sid -replace '[^A-Za-z0-9_\-]', '_'))
  if (-not (Test-Path $marker)) {
    $stamp = Join-Path $hub '.claude\sonelle_prune_stamp'
    $due = $true
    if (Test-Path $stamp) {
      $age = ((Get-Date) - (Get-Item $stamp).LastWriteTime).TotalDays
      if ($age -le 30) { $due = $false }
    }
    if ($due) {
      $nudge = 'sonelle: memory/ledger prune is due - run /prune (tools\prune.ps1 -Hub <hub>).'
      if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
      [System.IO.File]::WriteAllText($marker, (Get-Date).ToString('o'))
    }
  }
} catch { $nudge = '' }

function Write-Nudge([string]$text) {
  if (-not $text) { return }
  try { Write-Output (@{ systemMessage = $text } | ConvertTo-Json -Compress) } catch { Write-Output $text }
}

function Stop-Block([string]$msg) {
  $m = $msg
  if ($script:nudgeText) { $m = $m + "`n" + $script:nudgeText }
  [Console]::Error.WriteLine($m)
  exit 2
}
$script:nudgeText = $nudge

# --- find the last assistant message ---------------------------------------------------------------
$tp = [string]$j.transcript_path
if ((-not $tp) -or (-not (Test-Path $tp))) { Write-Nudge $nudge; exit 0 }

$lines = $null
try { $lines = @(Get-Content $tp -Tail 400 -ErrorAction Stop) } catch { $lines = $null }
if (-not $lines) { Write-Nudge $nudge; exit 0 }

$msg = $null
for ($i = $lines.Count - 1; $i -ge 0; $i--) {
  $o = $null
  try { $o = $lines[$i] | ConvertFrom-Json } catch { continue }
  if ($null -eq $o) { continue }
  if (($o.message) -and ([string]$o.message.role -eq 'assistant')) { $msg = $o.message; break }
}
if ($null -eq $msg) { Write-Nudge $nudge; exit 0 }

$content = $msg.content
if ($content -is [string]) {
  # a plain-string assistant message IS text - nothing to complain about beyond the canary
  $texts = @([string]$content)
} elseif ($content -is [System.Collections.IEnumerable]) {
  $texts = @()
  foreach ($b in $content) {
    if (($b) -and ([string]$b.type -eq 'text') -and ([string]$b.text).Trim()) { $texts += [string]$b.text }
  }
} else {
  Write-Nudge $nudge
  exit 0
}

# --- 1. text-for-the-owner -----------------------------------------------------------------------------
if ($texts.Count -eq 0) {
  Stop-Block ('sonelle: end the turn with TEXT for ' + $owner + ' (rule: feedback_final_text_after_tools).')
}

# --- 2. canary -------------------------------------------------------------------------------------
$canary = ''
try {
  $cfgPath = Join-Path $hub '.claude\sonelle.hub.json'
  if (Test-Path $cfgPath) {
    $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
    $canary = [string]$cfg.canary
  }
} catch { $canary = '' }

if ($canary.Trim()) {
  $first = $texts[0]
  $clean = $first -replace '^[\s>*_#`\-]+', ''
  if (-not $clean.StartsWith($canary.Trim(), [System.StringComparison]::OrdinalIgnoreCase)) {
    Stop-Block ('sonelle: start the message with "' + $canary.Trim() + '" (context-loss canary).')
  }
}

Write-Nudge $nudge
exit 0
