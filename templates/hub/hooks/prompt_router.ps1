<#
  prompt_router.ps1 - UserPromptSubmit hook (installed at <hub>\.claude\hooks\ by tools\install_hub.ps1).

  It never blocks a prompt. It reads the message, decides HOW the session should handle it, records that
  in a per-session state file the PreToolUse guards read, and injects at most a few lines of context:

    HOLD      "palauk / sustok / stop"  -> writes <hub>\_HOLD; hold_guard.ps1 then denies every edit,
                                           agent and workflow until a release word arrives.
    MODE      MINI | DELEGATE, and it is STICKY: a mode word ("mini" / "deleguok"...) sets the STANDING
              mode for the rest of the session, and every later prompt inherits it. Only QUESTION is
              per-prompt (answer first), and it leaves the standing mode alone. With no word yet, the
              standing mode is the hub default (<hub>\.claude\sonelle.hub.json "defaultMode", else MINI).
              Recomputing the mode from scratch on every prompt was the 2026-09-17 incident: "mini" said
              once was forgotten by the next prompt, and the guard denied one-line edits all session.
    DISPATCH  "<shortcode>: ..." -> the registry row's state sources, or a warning that the shortcode is
                                    not in PROJECTS.md (do not start work on a project that does not exist).

  State: %TEMP%\sonelle\mode_<session_id>.json = { mode, sticky, hold, fable_ok, short, ts }.
  `mode` = effective for THIS prompt (what main_agent_guard.ps1 reads), `sticky` = the standing mode.
  Hub root: two levels up from this script (<hub>\.claude\hooks\x.ps1), or $env:SONELLE_HUB for tests.
  Matching is done on a DIACRITIC-FLATTENED copy of the prompt, so "tesk" and the accented spelling both
  hit the same pure-ASCII regex (this file, like every .ps1 here, must stay ASCII for PS 5.1).
  Fail-OPEN: any read/parse problem exits 0 with no output.
#>
$ErrorActionPreference = 'SilentlyContinue'

try { $raw = (New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)).ReadToEnd() } catch { exit 0 }
if (-not $raw) { exit 0 }
try { $j = $raw | ConvertFrom-Json } catch { exit 0 }

# --- words that are NOT project shortcodes (configurable) -------------------------------------------
$NonProjectShorts = @('sonelle', 'mini', 'general', 'http', 'https', 'note', 'nb', 'ps', 'todo')

function Get-FlatText([string]$s) {
  if (-not $s) { return '' }
  try {
    $d = $s.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $d.ToCharArray()) {
      if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
    }
    return $sb.ToString()
  } catch { return $s }
}

# --- payload ---------------------------------------------------------------------------------------
$prompt = ''
foreach ($cand in @($j.prompt, $j.user_prompt, $j.message, $j.prompt_text)) {
  if (($cand -is [string]) -and $cand.Trim()) { $prompt = [string]$cand; break }
}
if ((-not $prompt) -and ($j.message) -and ($j.message.content -is [string])) { $prompt = [string]$j.message.content }
if (-not $prompt) { exit 0 }
$flat = (Get-FlatText $prompt)

$sid = [string]$j.session_id
if (-not $sid) { $sid = [string]$j.sessionId }
if (-not $sid) { $sid = 'nosession' }

$hub = $env:SONELLE_HUB
if (-not $hub) { $hub = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }
$holdFile = Join-Path $hub '_HOLD'
# <hub>\.claude\sonelle.hub.json (all optional): {"owner": "..."} = how a message names the hub owner,
# {"defaultMode": "MINI"|"DELEGATE"} = the standing mode a session starts in. Anything missing or
# unrecognised falls back to MINI - the SAFE direction, because the guard never blocks in MINI: a wrong
# default there costs a subagent that was not spawned, a wrong DELEGATE default costs a denied one-liner.
$owner = 'the user'
$hubDefaultMode = 'MINI'
try {
  $cfgP = Join-Path $hub '.claude\sonelle.hub.json'
  if (Test-Path $cfgP) {
    $cfg = Get-Content $cfgP -Raw | ConvertFrom-Json
    $o = $cfg.owner; if ($o) { $owner = [string]$o }
    $dm = [string]$cfg.defaultMode
    if ($dm -match '(?i)^\s*(MINI|DELEGATE)\s*$') { $hubDefaultMode = $dm.Trim().ToUpper() }
  }
} catch { }

$stateDir = Join-Path $env:TEMP 'sonelle'
try { if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null } } catch { exit 0 }
$statePath = Join-Path $stateDir ('mode_' + ($sid -replace '[^A-Za-z0-9_\-]', '_') + '.json')

$fableOk = $false
$short   = ''
$sticky  = ''
if (Test-Path $statePath) {
  try {
    $old = Get-Content $statePath -Raw | ConvertFrom-Json
    if ($old.fable_ok) { $fableOk = $true }
    $s = [string]$old.sticky
    if ($s -match '(?i)^\s*(MINI|DELEGATE)\s*$') { $sticky = $s.Trim().ToUpper() }
  } catch { }
}
if (-not $sticky) { $sticky = $hubDefaultMode }
$mode = $sticky

$u8    = New-Object System.Text.UTF8Encoding($false)
$lines = @()
$holdSet = $false

# --- a. HOLD set -----------------------------------------------------------------------------------
# A HOLD is a DIRECTIVE, so it has to be addressed to the session: the word opens the message (after an
# optional "name," or "short:" prefix) or stands alone on its own line. It is deliberately NOT "the word
# appears somewhere" - "stop" is an ordinary English/technical word ("where do you put the stop loss",
# "the tests stop at section 2"), and a HOLD set by accident freezes every session on this hub.
$holdWords = '(palauk|sustok|stok|stop)'
if (($flat -match ('(?i)^\s*(?:[\w\- ]+,\s*)?(?:[a-z0-9_\-]+\s*:\s*)?' + $holdWords + '\b')) -or
    ($flat -match ('(?im)^\s*' + $holdWords + '\s*[!.,]*\s*$'))) {
  $excerpt = $prompt
  if ($excerpt.Length -gt 120) { $excerpt = $excerpt.Substring(0, 120) + '...' }
  try { [System.IO.File]::WriteAllText($holdFile, ((Get-Date).ToString('o') + "`r`n" + $excerpt + "`r`n"), $u8) } catch { }
  $lines += ('sonelle: HOLD SET - full stop for all waves/agents/edits. Only zero-cost prep. Ask before anything else. (Release: start a message with ok/gerai/tesk/daryk/start/go/pirmyn/continue/tvarkyk, or delete ' + $holdFile + '.)')
  $holdSet = $true
}
# --- b. HOLD released ------------------------------------------------------------------------------
# a release word also opens the message, but an address or a lead-in clause may come first ("ne, tesk")
elseif ((Test-Path $holdFile) -and ($flat -match '(?i)^\s*(?:[\w\- ]+,\s*)?(ok|gerai|tesk|daryk|start|go|pirmyn|continue|tvarkyk)\b')) {
  try { Remove-Item $holdFile -Force } catch { }
  $lines += 'sonelle: HOLD RELEASED'
}

# --- c. Fable allowance ----------------------------------------------------------------------------
if ($flat -match '(?i)fable\s*ok') {
  $fableOk = $true
  $lines += 'sonelle: fable allowance ON for this session (a Fable subagent may be used once).'
}

if (-not $holdSet) {
  # --- d. mode -------------------------------------------------------------------------------------
  # Only an EXPLICIT word changes the standing mode; silence means "carry on as before". The old
  # "short prompt with no task verb -> MINI" heuristic is gone: it guessed the mode from prompt shape,
  # which is exactly what made a standing "mini" evaporate on the next sentence.
  $miniHit = [regex]::Match($flat, '(?i)\bmini\b')
  $delHit  = [regex]::Match($flat, '(?i)\b(deleguok|deleguoti|delegate|delegat\w*|agentams|agentui|subagent\w*|banga|bangos|bangas|workflow)\b')
  if ($miniHit.Success -and $delHit.Success) {
    # both words in one prompt: the one said FIRST is the instruction, the other is commentary
    if ($miniHit.Index -lt $delHit.Index) { $sticky = 'MINI' } else { $sticky = 'DELEGATE' }
  }
  elseif ($miniHit.Success) { $sticky = 'MINI' }
  elseif ($delHit.Success)  { $sticky = 'DELEGATE' }

  # a question is answered, not acted on - but it is a ONE-PROMPT state, it must not wipe the standing mode
  $isQuestion = ($prompt -match '\?\s*$') -or ($flat -match '(?i)^\s*(ar|kiek|kas|kodel|kaip|kur|kada|koks|kokia|kuris|why|what|how|is|are|does|do|can)\b')
  if ($isQuestion) { $mode = 'QUESTION' } else { $mode = $sticky }

  $standing = ''
  if ($mode -ne $sticky) { $standing = ' (standing: ' + $sticky + ')' }
  switch ($mode) {
    'DELEGATE' { $lines += ('sonelle mode: DELEGATE' + $standing + ' - write a self-contained brief and hand it to a subagent (Agent tool, model opus; review/verify with agentType reviewer/verifier). Main agent: orient + brief + integrate only; Edit/Write of code by the main agent is blocked (state files exempt). Say "mini" to do it inline. (standing; say "mini" to switch)') }
    'MINI'     { $lines += ('sonelle mode: MINI' + $standing + ' - do it yourself inline, no subagents unless needed. (standing for this session; say "deleguok" to switch)') }
    'QUESTION' { $lines += ('sonelle mode: QUESTION' + $standing + ' - answer first, do not act; act only after ' + $owner + ' says daryk/ok.') }
  }

  # --- e. dispatcher -------------------------------------------------------------------------------
  $m = [regex]::Match($prompt, '^\s*(?:[\w\- ]+,\s*)?([a-z0-9_\-]+)\s*:')
  if ($m.Success) {
    $cand = $m.Groups[1].Value
    $rest = $prompt.Substring($m.Length)
    $isPathish = ($rest -match '^[\\/]')
    if ((-not $isPathish) -and ($cand.Length -ge 2) -and ($NonProjectShorts -notcontains $cand)) {
      $short = $cand
      $reg = Join-Path $hub 'PROJECTS.md'
      $row = $null
      if (Test-Path $reg) {
        try {
          foreach ($ln in (Get-Content $reg)) {
            if ($ln -cmatch ('^\s*\|\s*' + [regex]::Escape($short) + '\s*\|')) { $row = $ln; break }
          }
        } catch { }
      }
      if ($row) {
        $cells = $row -split '\|'
        $src = ''
        if ($cells.Count -gt 5) { $src = $cells[5].Trim() }
        if (-not $src) { $src = '(state sources column is empty - read the project CLAUDE.md)' }
        $lines += ('sonelle dispatch: project ' + $short + ' -> read state sources first: ' + $src)
      } else {
        $lines += ('sonelle dispatch: "' + $short + '" is NOT in PROJECTS.md - do not start; ask whether to create it (_new_project.ps1) or fix the typo.')
      }
    }
  }
}

# --- state + output --------------------------------------------------------------------------------
try {
  $state = [ordered]@{ mode = $mode; sticky = $sticky; hold = [bool](Test-Path $holdFile); fable_ok = $fableOk; short = $short; ts = (Get-Date).ToString('o') }
  [System.IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json -Compress), $u8)
} catch { }

if ($lines.Count -gt 0) {
  $ctx = ($lines -join "`n")
  $out = @{ hookSpecificOutput = @{ hookEventName = 'UserPromptSubmit'; additionalContext = $ctx } }
  try { Write-Output ($out | ConvertTo-Json -Compress -Depth 5) } catch { }
}
exit 0
