<#
  selftest.d\hooks.ps1 - behavioral tests for the v1.47 enforcement hooks (templates\hub\hooks\*.ps1)
  and for tools\install_hub.ps1.

  Dot-sourced by tools\selftest.ps1 (which supplies $engine, $tmp, $ps and the Ok helper); also runnable
  on its own:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\selftest.d\hooks.ps1
  Every hook is fed a synthetic PreToolUse/Stop/UserPromptSubmit payload on stdin (as raw UTF-8 bytes via
  `cmd type`, the way Claude streams it) against a throwaway hub pointed at by $env:SONELLE_HUB.
#>

# --- standalone fallbacks (no-ops when dot-sourced by selftest.ps1) ---------------------------------
$sonelleHooksStandalone = (-not (Get-Command Ok -ErrorAction SilentlyContinue))
if ($sonelleHooksStandalone) {
  $ErrorActionPreference = 'Stop'
  $engine = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
  $tmp    = Join-Path $env:TEMP ('sonelle_selftest_hooks_' + $PID)
  if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
  New-Item -ItemType Directory -Path $tmp -Force | Out-Null
  $script:pass = 0
  $script:fail = 0
  function Ok($label, $cond) {
    if ($cond) { Write-Host ("  [PASS] {0}" -f $label) -ForegroundColor Green; $script:pass++ }
    else { Write-Host ("  [FAIL] {0}" -f $label) -ForegroundColor Red; $script:fail++ }
  }
  Write-Host "== selftest.d\hooks.ps1 (standalone) =="
}
if (-not $ps) { $ps = (Get-Process -Id $PID).Path }

$hookDir = Join-Path $engine 'templates\hub\hooks'
$hubT    = Join-Path $tmp 'hookhub'
$u8h     = New-Object System.Text.UTF8Encoding($false)
New-Item -ItemType Directory -Path (Join-Path $hubT '.claude') -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $hubT 'PROJECTS.md'), @"
# Registry

| Shortcode | Project | Code path | Git | State sources (read FIRST) | Keys |
|---|---|---|---|---|---|
| demo | Demo Project | C:\code\demo | yes | DEMO_TODO.txt + _demo_run_STATUS.md | none |
"@, $u8h)

$hIn  = Join-Path $tmp 'hook_in.json'
$hOut = Join-Path $tmp 'hook_out.txt'
$hErr = Join-Path $tmp 'hook_err.txt'
$savedHub = $env:SONELLE_HUB
$env:SONELLE_HUB = $hubT

function Invoke-SonelleHook([string]$hookName, $payload) {
  $hookPath = Join-Path $hookDir $hookName
  [System.IO.File]::WriteAllText($hIn, ($payload | ConvertTo-Json -Compress -Depth 8), $u8h)
  $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try {
    & cmd /c "type `"$hIn`" | `"$ps`" -NoProfile -ExecutionPolicy Bypass -File `"$hookPath`" > `"$hOut`" 2> `"$hErr`"" | Out-Null
  } finally { $ErrorActionPreference = $eap }
  $code = $LASTEXITCODE
  $o = ''; $e = ''
  try { $o = [string](Get-Content $hOut -Raw -ErrorAction SilentlyContinue) } catch { }
  try { $e = [string](Get-Content $hErr -Raw -ErrorAction SilentlyContinue) } catch { }
  return [pscustomobject]@{ Code = $code; Out = $o; Err = $e }
}
# session ids carry the PID: the hooks write real state into %TEMP%\sonelle\mode_<sid>.json, so two
# selftest runs at once must not share (or clean up) each other's session state.
function Invoke-SonelleHookRaw([string]$hookName, [string]$text) {
  $hookPath = Join-Path $hookDir $hookName
  [System.IO.File]::WriteAllText($hIn, $text, $u8h)
  $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try {
    & cmd /c "type `"$hIn`" | `"$ps`" -NoProfile -ExecutionPolicy Bypass -File `"$hookPath`" > `"$hOut`" 2> `"$hErr`"" | Out-Null
  } finally { $ErrorActionPreference = $eap }
  return $LASTEXITCODE
}
function New-Prompt([string]$sid, [string]$text) {
  return @{ session_id = ($sid + '_' + $PID); hook_event_name = 'UserPromptSubmit'; cwd = $hubT; prompt = $text }
}
function New-Pre([string]$sid, [string]$tool, $input_, $extra) {
  $p = @{ session_id = ($sid + '_' + $PID); hook_event_name = 'PreToolUse'; cwd = $hubT; tool_name = $tool; tool_input = $input_ }
  if ($extra) { foreach ($k in $extra.Keys) { $p[$k] = $extra[$k] } }
  return $p
}
function Write-Transcript([string]$path, [string[]]$lines) {
  [System.IO.File]::WriteAllText($path, (($lines -join "`r`n") + "`r`n"), $u8h)
}

$holdFile = Join-Path $hubT '_HOLD'
$codeFile = 'C:\code\demo\scripts\WeaponController.gd'

Write-Host "-- H1 prompt_router"
foreach ($n in @('prompt_router.ps1', 'hold_guard.ps1', 'main_agent_guard.ps1', 'reviewer_guard.ps1', 'stop_guard.ps1')) {
  Ok ("hook template exists: " + $n) (Test-Path (Join-Path $hookDir $n))
}
$r = Invoke-SonelleHook 'prompt_router.ps1' (New-Prompt 's1' 'palauk, nieko nedaryk kol nepasakysiu')
Ok "router: HOLD set writes _HOLD + says so" (($r.Code -eq 0) -and (Test-Path $holdFile) -and ($r.Out -match 'HOLD SET'))
$ctxOk = $false
try { $ctxOk = [bool](($r.Out | ConvertFrom-Json).hookSpecificOutput.additionalContext) } catch { $ctxOk = $false }
Ok "router output is valid JSON (additionalContext)" $ctxOk

Write-Host "-- H2 hold_guard (HOLD is active)"
$r = Invoke-SonelleHook 'hold_guard.ps1' (New-Pre 's1' 'Edit' @{ file_path = $codeFile; old_string = 'a'; new_string = 'b' } $null)
Ok "hold: Edit denied (exit 2)"        (($r.Code -eq 2) -and ($r.Err -match 'HOLD active'))
$r = Invoke-SonelleHook 'hold_guard.ps1' (New-Pre 's1' 'Bash' @{ command = 'git status' } $null)
Ok "hold: 'git status' allowed"        ($r.Code -eq 0)
$r = Invoke-SonelleHook 'hold_guard.ps1' (New-Pre 's1' 'Bash' @{ command = 'rm -rf build' } $null)
Ok "hold: 'rm -rf build' denied"       ($r.Code -eq 2)
$r = Invoke-SonelleHook 'hold_guard.ps1' (New-Pre 's1' 'Bash' @{ command = 'git status > out.txt' } $null)
Ok "hold: read-only + redirection denied" ($r.Code -eq 2)
$r = Invoke-SonelleHook 'hold_guard.ps1' (New-Pre 's1' 'Agent' @{ prompt = 'do work'; model = 'opus' } $null)
Ok "hold: Agent denied"                ($r.Code -eq 2)
$r = Invoke-SonelleHook 'hold_guard.ps1' (New-Pre 's1' 'Write' @{ file_path = $holdFile; content = 'x' } $null)
Ok "hold: editing _HOLD itself allowed" ($r.Code -eq 0)
$r = Invoke-SonelleHook 'hold_guard.ps1' (New-Pre 's1' 'Edit' @{ file_path = 'C:\code\demo\my_HOLD'; content = 'x' } $null)
Ok "hold: only the marker itself is exempt, not any *_HOLD file" ($r.Code -eq 2)
# a HOLD that only inspects the FIRST command in a chain is not a full stop
foreach ($c in @('git status && git push origin main', 'echo test; git reset --hard HEAD~5',
                 'dir & del C:\tmp\x.txt', 'ls; rmdir /s /q build', 'type a.txt; pip install evil',
                 'cat a.txt; npm run build', 'git status; git commit -am wip',
                 'find . -name "*.tmp" -delete', 'echo "$(rm -rf build)"')) {
  $r = Invoke-SonelleHook 'hold_guard.ps1' (New-Pre 's1' 'Bash' @{ command = $c } $null)
  Ok ("hold: chained/hidden mutation denied: " + $c) ($r.Code -eq 2)
}
foreach ($c in @('git log --oneline -5', 'cat a.txt | grep foo', 'python -c "print(1)"', 'Test-Path C:\x',
                 'grep -rn "Remove-Item" .', 'grep -rn "git commit" docs/')) {
  $r = Invoke-SonelleHook 'hold_guard.ps1' (New-Pre 's1' 'Bash' @{ command = $c } $null)
  Ok ("hold: read-only chain still allowed: " + $c) ($r.Code -eq 0)
}
# a mutating verb hidden in a substitution or behind a launcher word is still a mutation
foreach ($c in @('echo "$(' + [string][char]114 + [string][char]109 + ' -rf build)"',
                 'find . | xargs ' + [string][char]114 + [string][char]109 + ' -rf build')) {
  $r = Invoke-SonelleHook 'hold_guard.ps1' (New-Pre 's1' 'Bash' @{ command = $c } $null)
  Ok ("hold: disguised mutation denied: " + $c) ($r.Code -eq 2)
}
$r = Invoke-SonelleHook 'hold_guard.ps1' (New-Pre 's1' 'PowerShell' @{ command = 'Get-ChildItem; Rename-Item a b' } $null)
Ok "hold: PowerShell tool is guarded too"  ($r.Code -eq 2)
$r = Invoke-SonelleHook 'hold_guard.ps1' (New-Pre 's1' 'Workflow' @{ script = "agent('x')" } $null)
Ok "hold: Workflow denied"             ($r.Code -eq 2)
# coverage is an in-hook allowlist, not a matcher list: a tool nobody listed must not walk through a HOLD
$r = Invoke-SonelleHook 'hold_guard.ps1' (New-Pre 's1' 'mcp__db__apply_migration' @{ query = 'drop table x' } $null)
Ok "hold: an unlisted (MCP) write tool is denied" ($r.Code -eq 2)
$r = Invoke-SonelleHook 'hold_guard.ps1' (New-Pre 's1' 'mcp__db__list_tables' @{ } $null)
Ok "hold: a read-shaped MCP call still passes" ($r.Code -eq 0)
$r = Invoke-SonelleHook 'hold_guard.ps1' (New-Pre 's1' 'Read' @{ file_path = $codeFile } $null)
Ok "hold: Read allowed (orientation is zero-cost)" ($r.Code -eq 0)

$r = Invoke-SonelleHook 'prompt_router.ps1' (New-Prompt 's1' 'ok, tesk')
Ok "router: HOLD released"             (($r.Code -eq 0) -and (-not (Test-Path $holdFile)) -and ($r.Out -match 'HOLD RELEASED'))
$r = Invoke-SonelleHook 'hold_guard.ps1' (New-Pre 's1' 'Edit' @{ file_path = $codeFile } $null)
Ok "hold: after release, Edit allowed" ($r.Code -eq 0)

Write-Host "-- H1 modes + dispatch"
# the mode is STICKY and the hub default is MINI, so DELEGATE has to be ASKED for by name (see H1b)
$r = Invoke-SonelleHook 'prompt_router.ps1' (New-Prompt 's2' 'demo: deleguok agentams - pataisyk weapon config bug ir paleisk testus')
Ok "router: DELEGATE mode line"        ($r.Out -match 'mode: DELEGATE')
Ok "router: dispatch resolves a known shortcode to its state sources" ($r.Out -match 'dispatch: project demo .*DEMO_TODO\.txt')
$r = Invoke-SonelleHook 'prompt_router.ps1' (New-Prompt 's9' 'nesamone: pataisyk visa pasauli ir paleisk testus')
Ok "router: unknown shortcode warns instead of starting" ($r.Out -match 'NOT in PROJECTS\.md')
$r = Invoke-SonelleHook 'prompt_router.ps1' (New-Prompt 's3' 'mini: pataisyk typo README faile')
Ok "router: MINI mode line"            ($r.Out -match 'mode: MINI')
Ok "router: 'mini' is not treated as a project shortcode" (-not ($r.Out -match 'NOT in PROJECTS'))
$r = Invoke-SonelleHook 'prompt_router.ps1' (New-Prompt 's4' 'ar liko dar ka nors padaryti?')
Ok "router: QUESTION mode line"        ($r.Out -match 'mode: QUESTION')
$r = Invoke-SonelleHook 'prompt_router.ps1' (New-Prompt 's5' 'fable ok, demo: perdaryk architektura ir paleisk testus')
Ok "router: fable allowance recorded"  ($r.Out -match 'fable allowance ON')
$stateS5 = Join-Path (Join-Path $env:TEMP 'sonelle') ('mode_s5_' + $PID + '.json')
Ok "router: state file written"        ((Test-Path $stateS5) -and ((Get-Content $stateS5 -Raw) -match '"fable_ok":\s*true'))
# a diacritic-flattened release word must work too (LT is written both ways)
$r = Invoke-SonelleHook 'prompt_router.ps1' (New-Prompt 's6' 'stop')
Ok "router: bare 'stop' sets HOLD"     (Test-Path $holdFile)
$r = Invoke-SonelleHook 'prompt_router.ps1' (New-Prompt 's6' ('t' + [char]0x0119 + 'sk'))
Ok "router: accented release word works" (-not (Test-Path $holdFile))
# "stop" is an ordinary word: a HOLD is only set when it is ADDRESSED to the session (opens the message
# or stands alone), never because the word turns up somewhere inside a task.
foreach ($t in @('demo: kur dedi stop loss sitam setupui, pataisyk zurnala',
                 'perziurek Stop hook logika ir pataisyk',
                 'the selftest runs stop at section 2 - find out why and fix it',
                 'demo: nonstop spawnina priesus, pataisyk')) {
  $r = Invoke-SonelleHook 'prompt_router.ps1' (New-Prompt 's7' $t)
  Ok ("router: no accidental HOLD from: " + $t) ((-not (Test-Path $holdFile)) -and (-not ($r.Out -match 'HOLD SET')))
}
foreach ($t in @('palauk', 'sustok, nieko nedaryk', 'sonelle, palauk su bangomis', 'stop')) {
  $r = Invoke-SonelleHook 'prompt_router.ps1' (New-Prompt 's7' $t)
  Ok ("router: a real stop order still sets HOLD: " + $t) ((Test-Path $holdFile) -and ($r.Out -match 'HOLD SET'))
  Ok "router: the HOLD message says how to release it" ($r.Out -match 'Release:')
  $r2 = Invoke-SonelleHook 'prompt_router.ps1' (New-Prompt 's7' 'ne, tesk toliau')
  Ok "router: a lead-in clause before the release word still releases" (-not (Test-Path $holdFile))
}
# tolerant payload shapes (the prompt field name is not contractually fixed)
$r = Invoke-SonelleHook 'prompt_router.ps1' @{ session_id = ('s8a_' + $PID); hook_event_name = 'UserPromptSubmit'; cwd = $hubT; user_prompt = 'demo: deleguok - pataisyk bug ir paleisk testus' }
Ok "router: user_prompt field works"   ($r.Out -match 'mode: DELEGATE')
$r = Invoke-SonelleHook 'prompt_router.ps1' @{ session_id = ('s8b_' + $PID); hook_event_name = 'UserPromptSubmit'; cwd = $hubT; message = 'demo: deleguok - pataisyk bug ir paleisk testus' }
Ok "router: message field works"       ($r.Out -match 'mode: DELEGATE')

Write-Host "-- H1b sticky mode + hub defaultMode"
# The 2026-09-17 incident: the mode was recomputed from scratch on EVERY prompt, so "mini" said once was
# gone by the next sentence and the guard denied one-line edits for the rest of the session. The mode is
# a STANDING decision now; only an explicit word moves it, and QUESTION is the one per-prompt exception.
$hubCfgT = Join-Path $hubT '.claude\sonelle.hub.json'
function Get-ModeState([string]$sid) {
  $p = Join-Path (Join-Path $env:TEMP 'sonelle') ('mode_' + $sid + '_' + $PID + '.json')
  if (-not (Test-Path $p)) { return $null }
  try { return (Get-Content $p -Raw | ConvertFrom-Json) } catch { return $null }
}
# (a) no hub config at all -> the standing mode is MINI, the direction in which the guard never blocks
Ok "sticky: the test hub has no sonelle.hub.json yet" (-not (Test-Path $hubCfgT))
$r = Invoke-SonelleHook 'prompt_router.ps1' (New-Prompt 'sm1' 'pataisyk header spalva')
Ok "sticky: (a) no trigger word + default MINI -> MINI" ($r.Out -match 'mode: MINI')
$stM = Get-ModeState 'sm1'
Ok "sticky: (a) state records mode AND sticky" ($stM -and ($stM.mode -eq 'MINI') -and ($stM.sticky -eq 'MINI'))
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 'sm1' 'Edit' @{ file_path = $codeFile; old_string = 'a'; new_string = 'b' } $null)
Ok "sticky: (a) the guard allows the inline code Edit" ($r.Code -eq 0)
# (b) a hub can flip the default the other way
[System.IO.File]::WriteAllText($hubCfgT, '{ "defaultMode": "DELEGATE" }', $u8h)
$r = Invoke-SonelleHook 'prompt_router.ps1' (New-Prompt 'sm2' 'pataisyk header spalva')
Ok "sticky: (b) hub defaultMode DELEGATE -> DELEGATE" ($r.Out -match 'mode: DELEGATE')
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 'sm2' 'Edit' @{ file_path = $codeFile } $null)
Ok "sticky: (b) the guard denies the same Edit" (($r.Code -eq 2) -and ($r.Err -match 'DELEGATE mode'))
Ok "sticky: (b) the deny says how to switch" ($r.Err -match 'Say "mini" to switch this session to inline mode')
# an unknown value is not a licence to block: bad config falls back to MINI, never to DELEGATE
[System.IO.File]::WriteAllText($hubCfgT, '{ "defaultMode": "NONSENSE" }', $u8h)
$r = Invoke-SonelleHook 'prompt_router.ps1' (New-Prompt 'sm2b' 'pataisyk header spalva')
Ok "sticky: invalid defaultMode falls back to MINI" ($r.Out -match 'mode: MINI')
[System.IO.File]::WriteAllText($hubCfgT, '{ "owner": "Skipper" }', $u8h)
$r = Invoke-SonelleHook 'prompt_router.ps1' (New-Prompt 'sm2c' 'pataisyk header spalva')
Ok "sticky: a hub.json without defaultMode still means MINI" ($r.Out -match 'mode: MINI')
Remove-Item $hubCfgT -Force
# (c) "mini" once, and the NEXT prompt inherits it with no word at all
$r = Invoke-SonelleHook 'prompt_router.ps1' (New-Prompt 'sm3' 'mini, tiesiai i main')
Ok "sticky: (c) 'mini' sets the standing mode" ($r.Out -match 'mode: MINI')
Ok "sticky: (c) the MINI line says it is standing" ($r.Out -match 'standing for this session')
$r = Invoke-SonelleHook 'prompt_router.ps1' (New-Prompt 'sm3' 'pataisyk footer')
Ok "sticky: (c) the SECOND prompt is still MINI" ($r.Out -match 'mode: MINI')
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 'sm3' 'Edit' @{ file_path = $codeFile } $null)
Ok "sticky: (c) and the guard still allows the edit" ($r.Code -eq 0)
# (d) ... until a delegate word moves it
$r = Invoke-SonelleHook 'prompt_router.ps1' (New-Prompt 'sm3' 'deleguok sita banga')
Ok "sticky: (d) 'deleguok' switches to DELEGATE" ($r.Out -match 'mode: DELEGATE')
Ok "sticky: (d) the DELEGATE line says how to switch back" ($r.Out -match 'standing; say .{1,2}mini.{1,2} to switch')
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 'sm3' 'Edit' @{ file_path = $codeFile } $null)
Ok "sticky: (d) the guard denies again" ($r.Code -eq 2)
$r = Invoke-SonelleHook 'prompt_router.ps1' (New-Prompt 'sm3' 'pataisyk dar viena eilute')
Ok "sticky: (d) DELEGATE is standing too (next prompt inherits it)" ($r.Out -match 'mode: DELEGATE')
# (e) a question is answered first - but it is a ONE-PROMPT state, not a new standing mode
$r = Invoke-SonelleHook 'prompt_router.ps1' (New-Prompt 'sm4' 'mini, dirbam tiesiai')
Ok "sticky: (e) setup - standing MINI" ($r.Out -match 'mode: MINI')
$r = Invoke-SonelleHook 'prompt_router.ps1' (New-Prompt 'sm4' 'ar liko klaidu?')
Ok "sticky: (e) a question is QUESTION for this prompt" ($r.Out -match 'mode: QUESTION')
Ok "sticky: (e) the line names the standing mode it did not touch" ($r.Out -match 'QUESTION \(standing: MINI\)')
$stQ = Get-ModeState 'sm4'
Ok "sticky: (e) state keeps sticky MINI under mode QUESTION" ($stQ -and ($stQ.mode -eq 'QUESTION') -and ($stQ.sticky -eq 'MINI'))
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 'sm4' 'Edit' @{ file_path = $codeFile } $null)
Ok "sticky: (e) QUESTION still denies for this prompt" (($r.Code -eq 2) -and ($r.Err -match 'QUESTION mode'))
$r = Invoke-SonelleHook 'prompt_router.ps1' (New-Prompt 'sm4' 'pataisyk footer')
Ok "sticky: (e) the next non-question prompt is MINI again" ($r.Out -match 'mode: MINI')
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 'sm4' 'Edit' @{ file_path = $codeFile } $null)
Ok "sticky: (e) and the edit is allowed again" ($r.Code -eq 0)
# both words in one prompt: the one said FIRST is the instruction
$r = Invoke-SonelleHook 'prompt_router.ps1' (New-Prompt 'sm5' 'mini, nereikia deleguoti sito')
Ok "sticky: 'mini' before 'deleguoti' -> MINI" ($r.Out -match 'mode: MINI')
$r = Invoke-SonelleHook 'prompt_router.ps1' (New-Prompt 'sm6' 'deleguok agentams, ne mini')
Ok "sticky: 'deleguok' before 'mini' -> DELEGATE" ($r.Out -match 'mode: DELEGATE')
# the removed heuristic: a long prompt with a task verb must NOT become DELEGATE on shape alone
$r = Invoke-SonelleHook 'prompt_router.ps1' (New-Prompt 'sm7' 'demo: pataisyk weapon config bug, paleisk testus ir atnaujink ledgeri su rezultatais')
Ok "sticky: a long task prompt with no trigger stays MINI (old length/verb heuristic is gone)" ($r.Out -match 'mode: MINI')

Write-Host "-- H3 main_agent_guard"
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Edit' @{ file_path = $codeFile; old_string = 'a'; new_string = 'b' } $null)
Ok "delegate: main Edit on code denied" (($r.Code -eq 2) -and ($r.Err -match 'DELEGATE mode'))
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Write' @{ file_path = (Join-Path $hubT 'DEMO_TODO.txt'); content = 'x' } $null)
Ok "delegate: TODO state file allowed"  ($r.Code -eq 0)
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Write' @{ file_path = (Join-Path $hubT '_demo_run_STATUS.md'); content = 'x' } $null)
Ok "delegate: ledger allowed"           ($r.Code -eq 0)
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Write' @{ file_path = (Join-Path $hubT 'memory\project_demo.md'); content = 'x' } $null)
Ok "delegate: memory allowed"           ($r.Code -eq 0)
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Write' @{ file_path = (Join-Path $hubT '_demo_wave_SPEC.md'); content = 'x' } $null)
Ok "delegate: _*_SPEC.md brief allowed" ($r.Code -eq 0)
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Edit' @{ file_path = $codeFile } @{ agent_id = 'ag_123'; agent_type = 'implementer' })
Ok "delegate: subagent edit allowed"    ($r.Code -eq 0)
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's3' 'Edit' @{ file_path = $codeFile } $null)
Ok "mini: main Edit on code allowed"    ($r.Code -eq 0)
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's4' 'Edit' @{ file_path = $codeFile } $null)
Ok "question: main Edit on code denied" (($r.Code -eq 2) -and ($r.Err -match 'QUESTION mode'))
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 'no_such_session' 'Edit' @{ file_path = $codeFile } $null)
Ok "no mode recorded: no opinion (allow)" ($r.Code -eq 0)
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Agent' @{ prompt = 'review this'; model = 'fable' } $null)
Ok "tiering: Agent model fable denied"  (($r.Code -eq 2) -and ($r.Err -match 'Model tiering'))
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Agent' @{ prompt = 'review this'; model = 'opus' } $null)
Ok "tiering: Agent model opus allowed"  ($r.Code -eq 0)
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's5' 'Agent' @{ prompt = 'review this'; model = 'fable' } $null)
Ok "tiering: fable allowed after 'fable ok'" ($r.Code -eq 0)
$wfFable = "agent('do x', { model: 'fable', effort: 'high' })"
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Workflow' @{ script = $wfFable } $null)
Ok "tiering: Workflow script with model fable denied" ($r.Code -eq 2)
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Workflow' @{ script = "agent('do x', { model: 'opus' })" } $null)
Ok "tiering: Workflow script with model opus allowed" ($r.Code -eq 0)
$wfPath = Join-Path $tmp 'wave_fable.js'
[System.IO.File]::WriteAllText($wfPath, $wfFable, $u8h)
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Workflow' @{ scriptPath = $wfPath } $null)
Ok "tiering: Workflow scriptPath is read from disk" ($r.Code -eq 2)

# the engine ships NO personal name: how a block message addresses the hub owner comes from hub config
[System.IO.File]::WriteAllText((Join-Path $hubT '.claude\sonelle.hub.json'), '{ "owner": "Skipper" }', $u8h)
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Edit' @{ file_path = $codeFile } $null)
Ok "owner name comes from sonelle.hub.json" (($r.Code -eq 2) -and ($r.Err -match 'Skipper says "mini"'))
Remove-Item (Join-Path $hubT '.claude\sonelle.hub.json') -Force
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Edit' @{ file_path = $codeFile } $null)
Ok "no owner configured: neutral wording, still denies" (($r.Code -eq 2) -and ($r.Err -match 'the user says "mini"'))
# writing code through a SHELL is the same rule (the loophole a model takes when Edit is denied)
foreach ($c in @('cat > C:\code\demo\src\a.gd <<EOF', 'echo x >> C:\code\demo\src\a.gd',
                 'sed -i s/a/b/ C:\code\demo\src\a.gd')) {
  $r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Bash' @{ command = $c } $null)
  Ok ("delegate: shell write denied: " + $c) (($r.Code -eq 2) -and ($r.Err -match 'DELEGATE mode'))
}
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'PowerShell' @{ command = "Set-Content C:\code\demo\src\a.gd 'x'" } $null)
Ok "delegate: PowerShell Set-Content denied" ($r.Code -eq 2)
# ... including when the write verb hides in a nested shell or behind a launcher word
foreach ($c in @('sh -c "Set-Content C:\code\demo\src\a.gd 1"', 'sudo tee C:\code\demo\src\a.gd',
                 'xargs Set-Content C:\code\demo\src\a.gd')) {
  $r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Bash' @{ command = $c } $null)
  Ok ("delegate: disguised shell write denied: " + $c) ($r.Code -eq 2)
}
foreach ($c in @('git status', 'powershell -NoProfile -File tools\selftest.ps1', 'pytest -q > /dev/null',
                 'grep -rn "a->b" src', 'echo done >> C:\hub\DEMO_TODO.txt',
                 'grep -rn "Set-Content" tools/', 'git diff --stat')) {
  $r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Bash' @{ command = $c } $null)
  Ok ("delegate: non-writing / exempt shell command allowed: " + $c) ($r.Code -eq 0)
}
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's3' 'Bash' @{ command = 'echo x > C:\code\demo\src\a.gd' } $null)
Ok "mini: shell write allowed"          ($r.Code -eq 0)
# (f) a commit TRAILER is not a redirect. `Co-Authored-By: X <noreply@anthropic.com>` used to be denied
# because the closing `>` of the address matched the redirect regex - which blocked the one shell command
# the end-of-work ritual actually needs (2026-09-17).
$heredocCommit = "git commit -F - <<'EOF'`nv1.47.1: sticky mode`n`nCo-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`nEOF"
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Bash' @{ command = $heredocCommit } $null)
Ok "delegate: (f) git commit heredoc with an <e-mail> trailer allowed" ($r.Code -eq 0)
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Bash' @{ command = 'git commit -m "perf: a > b in the hot loop"' } $null)
Ok "delegate: '>' inside a quoted git commit message is not a redirect" ($r.Code -eq 0)
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Bash' @{ command = 'git log --format="%an <%ae>" -5' } $null)
Ok "delegate: angle brackets in a quoted git format string are not a redirect" ($r.Code -eq 0)
# ... and the exclusion must not become a loophole: an unquoted redirect, or one inside a NESTED SHELL,
# is still a write even when the line starts with `git`.
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Bash' @{ command = 'git show HEAD:src/a.ts > C:\code\demo\src\a.ts' } $null)
Ok "delegate: an unquoted redirect after git is still denied" ($r.Code -eq 2)
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Bash' @{ command = 'git status && sh -c "echo x > src\a.ts"' } $null)
Ok "delegate: a redirect quoted into a nested shell is still denied" ($r.Code -eq 2)
# (g) the plain case the exclusion must never touch
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Bash' @{ command = 'cat > src\a.ts' } $null)
Ok "delegate: (g) 'cat > src\a.ts' still denied" (($r.Code -eq 2) -and ($r.Err -match 'DELEGATE mode'))
# the scratchpad exemption is a PATH COMPONENT, not a substring of a filename
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Edit' @{ file_path = 'C:\code\demo\scratchpad_evil.gd' } $null)
Ok "delegate: 'scratchpad' inside a FILENAME is not an exemption" ($r.Code -eq 2)
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Edit' @{ file_path = 'C:\code\demo\scratchpad\notes.gd' } $null)
Ok "delegate: a real scratchpad DIR is exempt" ($r.Code -eq 0)
# caller detection: agent_id is the contract; a type alone only excuses a SUBAGENT role
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Edit' @{ file_path = $codeFile } @{ agent_type = 'implementer' })
Ok "subagent role (agent_type only) allowed" ($r.Code -eq 0)
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Edit' @{ file_path = $codeFile } @{ agent_type = 'main' })
Ok "agent_type 'main' is NOT a subagent (still denied)" ($r.Code -eq 2)
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Edit' @{ file_path = $codeFile } @{ agentId = 'ag_9' })
Ok "camelCase agentId is honored"       ($r.Code -eq 0)
$r = Invoke-SonelleHook 'main_agent_guard.ps1' @{ sessionId = ('s2_' + $PID); hook_event_name = 'PreToolUse'; tool_name = 'Edit'; tool_input = @{ file_path = $codeFile } }
Ok "camelCase sessionId finds the mode state" ($r.Code -eq 2)
# caller detection, second signal: transcript_path. agent_id/agent_type are UNVERIFIED for subagent calls,
# so a subagent transcript path (a `subagents` dir component and/or an `agent-<hex>.jsonl` leaf) excuses the
# call on its own - otherwise DELEGATE would deny the subagent it just delegated the work to.
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Edit' @{ file_path = $codeFile } @{ transcript_path = 'C:\x\.claude\projects\p\subagents\agent-abcdef1234.jsonl' })
Ok "subagent transcript_path (subagents\agent-<hex>.jsonl) allowed" ($r.Code -eq 0)
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Edit' @{ file_path = $codeFile } @{ transcript_path = 'C:\x\.claude\projects\p\subagents\workflows\wf_1\agent-0123abcd4567.jsonl' })
Ok "workflow subagent transcript_path allowed" ($r.Code -eq 0)
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Edit' @{ file_path = $codeFile } @{ transcript_path = 'C:\x\.claude\projects\p\agent-0123abcd4567.jsonl' })
Ok "agent-<hex>.jsonl leaf alone is enough" ($r.Code -eq 0)
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Bash' @{ command = 'echo x > C:\code\demo\src\a.gd' } @{ transcript_path = 'C:\x\.claude\projects\p\subagents\agent-abcdef1234.jsonl' })
Ok "subagent transcript_path excuses a shell write too" ($r.Code -eq 0)
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Edit' @{ file_path = $codeFile } @{ transcript_path = 'C:\x\.claude\projects\p\1234-5678.jsonl' })
Ok "main transcript_path (<uuid>.jsonl) is NOT a subagent (still denied)" ($r.Code -eq 2)
foreach ($tp in @('', '   ', 'C:\x\.claude\projects\p\subagents_notadir\a.jsonl', 'C:\x\agent-zzzz.jsonl')) {
  $r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Edit' @{ file_path = $codeFile } @{ transcript_path = $tp })
  Ok ("malformed/non-subagent transcript_path falls back to the old rule: '" + $tp + "'") ($r.Code -eq 2)
}
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Edit' @{ file_path = $codeFile } @{ transcript_path = 12345 })
Ok "non-string transcript_path falls back to the old rule" ($r.Code -eq 2)
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Edit' @{ file_path = $codeFile } @{ transcript_path = @{ p = 'x' } })
Ok "object transcript_path falls back to the old rule" ($r.Code -eq 2)
# the new signal is an excuse for the DELEGATE rule only - tiering must judge the call unchanged
$r = Invoke-SonelleHook 'main_agent_guard.ps1' (New-Pre 's2' 'Agent' @{ prompt = 'x'; model = 'fable' } @{ transcript_path = 'C:\x\.claude\projects\p\subagents\agent-abcdef1234.jsonl' })
Ok "tiering unchanged by the transcript signal (fable still denied)" ($r.Code -eq 2)

Write-Host "-- H4 reviewer_guard"
$rev = @{ agent_id = 'ag_r1'; agent_type = 'reviewer' }
$r = Invoke-SonelleHook 'reviewer_guard.ps1' (New-Pre 's2' 'Write' @{ file_path = $codeFile; content = 'x' } $rev)
Ok "reviewer: Write denied"            (($r.Code -eq 2) -and ($r.Err -match 'review-only'))
$r = Invoke-SonelleHook 'reviewer_guard.ps1' (New-Pre 's2' 'Bash' @{ command = 'rm -rf build' } $rev)
Ok "reviewer: rm denied"               ($r.Code -eq 2)
$r = Invoke-SonelleHook 'reviewer_guard.ps1' (New-Pre 's2' 'Bash' @{ command = 'git add -A' } $rev)
Ok "reviewer: git add denied"          ($r.Code -eq 2)
$r = Invoke-SonelleHook 'reviewer_guard.ps1' (New-Pre 's2' 'Bash' @{ command = 'echo hi > note.txt' } $rev)
Ok "reviewer: redirection denied"      ($r.Code -eq 2)
$r = Invoke-SonelleHook 'reviewer_guard.ps1' (New-Pre 's2' 'Bash' @{ command = 'git status' } $rev)
Ok "reviewer: git status allowed"      ($r.Code -eq 0)
$r = Invoke-SonelleHook 'reviewer_guard.ps1' (New-Pre 's2' 'Bash' @{ command = 'powershell -NoProfile -File tools\selftest.ps1' } $rev)
Ok "reviewer: test runner allowed"     ($r.Code -eq 0)
$r = Invoke-SonelleHook 'reviewer_guard.ps1' (New-Pre 's2' 'Bash' @{ command = 'pytest -q' } $rev)
Ok "reviewer: pytest allowed"          ($r.Code -eq 0)
$r = Invoke-SonelleHook 'reviewer_guard.ps1' (New-Pre 's2' 'Write' @{ file_path = $codeFile; content = 'x' } @{ agent_id = 'ag_i1'; agent_type = 'implementer' })
Ok "implementer: Write allowed"        ($r.Code -eq 0)
$r = Invoke-SonelleHook 'reviewer_guard.ps1' (New-Pre 's2' 'Write' @{ file_path = $codeFile; content = 'x' } $null)
Ok "main agent: reviewer_guard stays out of the way" ($r.Code -eq 0)
# a test-runner word must not launder the rest of the command line
foreach ($c in @('rm -rf build && pytest -q', 'git push origin main; npm test', 'pytest && rm -rf important',
                 'echo x > f.txt; pytest', 'powershell -File tools/selftest.ps1; git push')) {
  $r = Invoke-SonelleHook 'reviewer_guard.ps1' (New-Pre 's2' 'Bash' @{ command = $c } $rev)
  Ok ("reviewer: test-runner word does not exempt a chain: " + $c) ($r.Code -eq 2)
}
# a newline is a command separator too (multi-line commands are the normal shape)
$r = Invoke-SonelleHook 'reviewer_guard.ps1' (New-Pre 's2' 'Bash' @{ command = "git status`nrm -rf build" } $rev)
Ok "reviewer: multi-line command is judged line by line" ($r.Code -eq 2)
$r = Invoke-SonelleHook 'reviewer_guard.ps1' (New-Pre 's2' 'PowerShell' @{ command = "cd src`nSet-Content out.txt 'x'" } $rev)
Ok "reviewer: multi-line PowerShell write denied" ($r.Code -eq 2)
# a nested shell is not a disguise
foreach ($c in @('sh -c "rm -rf build"', 'bash -c "git add -A"', 'powershell -Command "Remove-Item C:\repo\file.ps1"')) {
  $r = Invoke-SonelleHook 'reviewer_guard.ps1' (New-Pre 's2' 'Bash' @{ command = $c } $rev)
  Ok ("reviewer: nested shell denied: " + $c) ($r.Code -eq 2)
}
$r = Invoke-SonelleHook 'reviewer_guard.ps1' (New-Pre 's2' 'Bash' @{ command = 'find . -name "*.ps1" -delete' } $rev)
Ok "reviewer: find -delete denied"     ($r.Code -eq 2)
# a launcher word (sudo/xargs/time/env/...) keeps the verb off the start of its segment - the anchored
# deny patterns must see through it, and through a command substitution.
$delCmd = [string][char]114 + [string][char]109      # the two-letter delete command, spelled at runtime
foreach ($c in @(('sudo ' + $delCmd + ' -rf build'), ('env ' + $delCmd + ' -rf build'),
                 ('nohup ' + $delCmd + ' -rf build'), ('time ' + $delCmd + ' -rf build'),
                 ('command ' + $delCmd + ' -rf build'), ('find . | xargs ' + $delCmd + ' -rf build'),
                 ('git ls-files | xargs sed -i s/a/b/'), ('$(' + $delCmd + ' -rf build)'),
                 ("sh -c '" + $delCmd + " -rf build'"))) {
  $r = Invoke-SonelleHook 'reviewer_guard.ps1' (New-Pre 's2' 'Bash' @{ command = $c } $rev)
  Ok ("reviewer: launcher/substitution does not hide the verb: " + $c) ($r.Code -eq 2)
}
# ... while QUOTING a verb as evidence is exactly what a review does, so it must not be denied for it
foreach ($c in @('grep -rn "Remove-Item" .', 'grep -rn "git commit" docs/', 'rg "New-Item" -n tools/',
                 'grep -rn "npm install" package.json')) {
  $r = Invoke-SonelleHook 'reviewer_guard.ps1' (New-Pre 's2' 'Bash' @{ command = $c } $rev)
  Ok ("reviewer: quoted verb as evidence allowed: " + $c) ($r.Code -eq 0)
}
# ... and the read-only evidence commands a review actually needs stay usable
foreach ($c in @('grep -n "a->b" src/x.c', 'cat x.txt 2>/dev/null', 'git diff --stat', 'go test ./...',
                 'npm test', 'dotnet test')) {
  $r = Invoke-SonelleHook 'reviewer_guard.ps1' (New-Pre 's2' 'Bash' @{ command = $c } $rev)
  Ok ("reviewer: read-only/test command allowed: " + $c) ($r.Code -eq 0)
}
$ver = @{ agent_id = 'ag_v1'; agentType = 'verifier' }
$r = Invoke-SonelleHook 'reviewer_guard.ps1' (New-Pre 's2' 'Bash' @{ command = 'rm -rf build' } $ver)
Ok "verifier (camelCase agentType) is guarded too" ($r.Code -eq 2)
$r = Invoke-SonelleHook 'reviewer_guard.ps1' (New-Pre 's2' 'PowerShell' @{ command = 'Remove-Item C:\x' } @{ subagent_type = 'reviewer' })
Ok "reviewer via subagent_type + PowerShell denied" ($r.Code -eq 2)

Write-Host "-- H5 stop_guard"
$trOk    = Join-Path $tmp 'tr_ok.jsonl'
$trTool  = Join-Path $tmp 'tr_tool.jsonl'
$trJunk  = Join-Path $tmp 'tr_junk.jsonl'
$asstTxt = '{"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"hm"},{"type":"text","text":"Skipper, padaryta - testai zali."}]}}'
$asstBad = '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Padaryta - testai zali."}]}}'
$asstTool= '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls"}}]}}'
$sysLine = '{"type":"system","subtype":"info"}'
Write-Transcript $trOk   @($asstTool, $asstTxt, $sysLine)
Write-Transcript $trTool @($asstTxt, $asstTool, $sysLine)
Write-Transcript $trJunk @('not json at all', '{"broken":', 'x')
function New-Stop([string]$sid, [string]$tp, $active) {
  return @{ session_id = ($sid + '_' + $PID); hook_event_name = 'Stop'; transcript_path = $tp; stop_hook_active = $active }
}
$r = Invoke-SonelleHook 'stop_guard.ps1' (New-Stop 'p1' $trTool $false)
Ok "stop: tool-only final message blocked" (($r.Code -eq 2) -and ($r.Err -match 'end the turn with TEXT'))
$r = Invoke-SonelleHook 'stop_guard.ps1' (New-Stop 'p2' $trOk $false)
Ok "stop: final text passes (no canary configured)" ($r.Code -eq 0)
Ok "stop: prune nudge printed when no stamp exists"  ($r.Out -match 'prune is due')
$r = Invoke-SonelleHook 'stop_guard.ps1' (New-Stop 'p2' $trOk $false)
Ok "stop: nudge is once per session (not every turn)" (-not ($r.Out -match 'prune is due'))
[System.IO.File]::WriteAllText((Join-Path $hubT '.claude\sonelle_prune_stamp'), (Get-Date).ToString('o'), $u8h)
$r = Invoke-SonelleHook 'stop_guard.ps1' (New-Stop 'p3' $trOk $false)
Ok "stop: fresh prune stamp silences the nudge" (-not ($r.Out -match 'prune is due'))
[System.IO.File]::WriteAllText((Join-Path $hubT '.claude\sonelle.hub.json'), '{ "canary": "Skipper," }', $u8h)
Write-Transcript $trOk @($asstTool, $asstBad, $sysLine)
$r = Invoke-SonelleHook 'stop_guard.ps1' (New-Stop 'p4' $trOk $false)
Ok "stop: missing canary blocked"      (($r.Code -eq 2) -and ($r.Err -match 'context-loss canary'))
Write-Transcript $trOk @($asstTool, $asstTxt, $sysLine)
$r = Invoke-SonelleHook 'stop_guard.ps1' (New-Stop 'p5' $trOk $false)
Ok "stop: canary present passes"       ($r.Code -eq 0)
$r = Invoke-SonelleHook 'stop_guard.ps1' (New-Stop 'p6' $trJunk $false)
Ok "stop: garbage transcript fails open" ($r.Code -eq 0)
$r = Invoke-SonelleHook 'stop_guard.ps1' (New-Stop 'p7' (Join-Path $tmp 'no_such_transcript.jsonl') $false)
Ok "stop: missing transcript fails open" ($r.Code -eq 0)
$r = Invoke-SonelleHook 'stop_guard.ps1' (New-Stop 'p8' $trTool $true)
Ok "stop: stop_hook_active short-circuits (no loop)" ($r.Code -eq 0)
[System.IO.File]::WriteAllText((Join-Path $hubT '.claude\sonelle.hub.json'), '{ "canary": "" }', $u8h)
Write-Transcript $trOk @($asstTool, $asstBad, $sysLine)
$r = Invoke-SonelleHook 'stop_guard.ps1' (New-Stop 'p9' $trOk $false)
Ok "stop: empty canary disables the check" ($r.Code -eq 0)
$r = Invoke-SonelleHook 'stop_guard.ps1' @{ session_id = ('p10_' + $PID); hook_event_name = 'Stop' }
Ok "stop: payload with no transcript_path fails open" ($r.Code -eq 0)

Write-Host "-- fail-open (a guard must never break a working session)"
# the fail-open guarantee is BEHAVIORAL: feed every hook empty stdin, junk, valid JSON that is not a
# payload, and a payload with no tool_input - each must exit 0 and print nothing on stderr.
foreach ($n in @('prompt_router.ps1', 'hold_guard.ps1', 'main_agent_guard.ps1', 'reviewer_guard.ps1', 'stop_guard.ps1')) {
  $codes = @()
  foreach ($txt in @('', '   ', 'not json at all', '{"broken":', '[]', '{"tool_name":"Edit"}', '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":null}')) {
    $codes += (Invoke-SonelleHookRaw $n $txt)
  }
  Ok ($n + ': fails open on empty/garbage/partial stdin') ((@($codes | Where-Object { $_ -ne 0 }).Count -eq 0))
}

Write-Host "-- install_hub (merge / idempotent / uninstall)"
$env:SONELLE_HUB = $savedHub
$ihHub = Join-Path $tmp 'installhub'
New-Item -ItemType Directory -Path (Join-Path $ihHub '.claude') -Force | Out-Null
$preExisting = @'
{
  "permissions": { "allow": ["Bash(git status)"], "deny": [] },
  "hooks": {
    "SessionStart": [ { "matcher": "startup", "hooks": [ { "type": "command", "command": "powershell -File .claude/hooks/mine.ps1" } ] } ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "powershell -File .claude/hooks/my_stop_guard.ps1" } ] },
      { "hooks": [ { "type": "command", "command": "powershell -File tools/hooks/stop_guard.ps1" } ] }
    ]
  }
}
'@
[System.IO.File]::WriteAllText((Join-Path $ihHub '.claude\settings.json'), $preExisting, $u8h)
$ihOut = & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $engine 'tools\install_hub.ps1') -Hub $ihHub -Quiet
Ok "install_hub exit 0"                ($LASTEXITCODE -eq 0)
$ihSetPath = Join-Path $ihHub '.claude\settings.json'
$ihSet = $null; try { $ihSet = Get-Content $ihSetPath -Raw | ConvertFrom-Json } catch { }
Ok "install_hub keeps permissions"     ($ihSet -and ($ihSet.permissions.allow -contains 'Bash(git status)'))
Ok "install_hub keeps a pre-existing hook" ($ihSet -and (($ihSet.hooks.SessionStart | ConvertTo-Json -Depth 8) -match 'mine\.ps1'))
$ihRaw = Get-Content $ihSetPath -Raw
Ok "install_hub registers all five hooks" ((($ihRaw -match '\.claude/hooks/prompt_router\.ps1') -and ($ihRaw -match '\.claude/hooks/hold_guard\.ps1') -and ($ihRaw -match '\.claude/hooks/main_agent_guard\.ps1') -and ($ihRaw -match '\.claude/hooks/reviewer_guard\.ps1') -and ($ihRaw -match '\.claude/hooks/stop_guard\.ps1')))
Ok "install_hub copies the hook files" ((Test-Path (Join-Path $ihHub '.claude\hooks\prompt_router.ps1')) -and (Test-Path (Join-Path $ihHub '.claude\hooks\stop_guard.ps1')))
Ok "install_hub writes a manifest"     (Test-Path (Join-Path $ihHub '.claude\sonelle.install.json'))
# "your permissions and any other hooks are kept" has to hold for a hook whose NAME contains one of ours
Ok "install_hub keeps a foreign hook named like ours" (($ihRaw -match 'my_stop_guard\.ps1') -and ($ihRaw -match 'tools/hooks/stop_guard\.ps1'))
# the commands (Agent C) and the subagents (Agent B) are copied when the engine ships them
$cmdSrc = Join-Path $engine 'templates\hub\commands'
if (Test-Path $cmdSrc) {
  $want = @(Get-ChildItem $cmdSrc -File | ForEach-Object { $_.Name })
  $got  = @(Get-ChildItem (Join-Path $ihHub '.claude\commands') -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
  Ok "install_hub copies templates\hub\commands" (($want.Count -gt 0) -and (@($want | Where-Object { $got -notcontains $_ }).Count -eq 0))
  # the installer is the only place that knows both paths, so a copied command carries no placeholders
  $cmdTxt = ((Get-ChildItem (Join-Path $ihHub '.claude\commands') -File -ErrorAction SilentlyContinue | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n")
  Ok "install_hub fills <engine>/<hub> into the copied commands" (($cmdTxt) -and (-not ($cmdTxt -match '<engine>')) -and ($cmdTxt -match [regex]::Escape($engine)))
}
$agSrc = Join-Path $engine 'templates\agents'
if (Test-Path $agSrc) {
  $want = @(Get-ChildItem $agSrc -File | ForEach-Object { $_.Name })
  $got  = @(Get-ChildItem (Join-Path $ihHub '.claude\agents') -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
  Ok "install_hub copies templates\agents into the hub" (($want.Count -gt 0) -and (@($want | Where-Object { $got -notcontains $_ }).Count -eq 0))
}
& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $engine 'tools\install_hub.ps1') -Hub $ihHub -Quiet | Out-Null
$ihRaw2 = Get-Content $ihSetPath -Raw
Ok "install_hub is idempotent (second run = same settings)" ($ihRaw2 -eq $ihRaw)
Ok "install_hub did not duplicate entries" ((([regex]::Matches($ihRaw2, '\.claude/hooks/stop_guard\.ps1')).Count -eq 1))
& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $engine 'tools\install_hub.ps1') -Hub $ihHub -Canary 'Skipper,' -Owner 'Skipper' -Quiet | Out-Null
$ihCan = $null; try { $ihCan = Get-Content (Join-Path $ihHub '.claude\sonelle.hub.json') -Raw | ConvertFrom-Json } catch { }
Ok "install_hub -Canary/-Owner write sonelle.hub.json" ($ihCan -and ($ihCan.canary -eq 'Skipper,') -and ($ihCan.owner -eq 'Skipper'))
& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $engine 'tools\install_hub.ps1') -Hub $ihHub -DefaultMode 'delegate' -Quiet | Out-Null
$ihCfg = $null; try { $ihCfg = Get-Content (Join-Path $ihHub '.claude\sonelle.hub.json') -Raw | ConvertFrom-Json } catch { }
Ok "install_hub -DefaultMode writes it normalised" ($ihCfg -and ($ihCfg.defaultMode -eq 'DELEGATE'))
Ok "install_hub -DefaultMode keeps the other hub.json keys" ($ihCfg -and ($ihCfg.canary -eq 'Skipper,') -and ($ihCfg.owner -eq 'Skipper'))
& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $engine 'tools\install_hub.ps1') -Hub $ihHub -DefaultMode 'ARBITRARY' -Quiet | Out-Null
Ok "install_hub refuses a bogus -DefaultMode (exit 1)" ($LASTEXITCODE -eq 1)
$ihCfg2 = $null; try { $ihCfg2 = Get-Content (Join-Path $ihHub '.claude\sonelle.hub.json') -Raw | ConvertFrom-Json } catch { }
Ok "a refused -DefaultMode leaves the previous value alone" ($ihCfg2 -and ($ihCfg2.defaultMode -eq 'DELEGATE'))
& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $engine 'tools\install_hub.ps1') -Hub $ihHub -Quiet | Out-Null
Ok "install_hub without -DefaultMode does not touch it" (((Get-Content (Join-Path $ihHub '.claude\sonelle.hub.json') -Raw | ConvertFrom-Json).defaultMode) -eq 'DELEGATE')
& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $engine 'tools\install_hub.ps1') -Hub $ihHub -Uninstall -Quiet | Out-Null
Ok "uninstall exit 0"                  ($LASTEXITCODE -eq 0)
$ihSet3 = $null; try { $ihSet3 = Get-Content $ihSetPath -Raw | ConvertFrom-Json } catch { }
$ihRaw3 = Get-Content $ihSetPath -Raw
Ok "uninstall removes every sonelle hook entry" (-not ($ihRaw3 -match '\.claude/hooks/(prompt_router|hold_guard|main_agent_guard|reviewer_guard|stop_guard)\.ps1'))
Ok "uninstall keeps permissions + the foreign hook" ($ihSet3 -and ($ihSet3.permissions.allow -contains 'Bash(git status)') -and ($ihRaw3 -match 'mine\.ps1'))
Ok "uninstall keeps the look-alike foreign hooks" (($ihRaw3 -match 'my_stop_guard\.ps1') -and ($ihRaw3 -match 'tools/hooks/stop_guard\.ps1'))
Ok "uninstall removes the hook files + manifest" ((-not (Test-Path (Join-Path $ihHub '.claude\hooks\prompt_router.ps1'))) -and (-not (Test-Path (Join-Path $ihHub '.claude\sonelle.install.json'))))
Ok "uninstall leaves sonelle.hub.json alone" (Test-Path (Join-Path $ihHub '.claude\sonelle.hub.json'))
& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $engine 'tools\install_hub.ps1') -Hub $engine -Quiet | Out-Null
Ok "install_hub refuses the engine as a hub (exit 1)" ($LASTEXITCODE -eq 1)
Ok "engine .claude/settings.json untouched by the refusal" (-not ((Get-Content (Join-Path $engine '.claude\settings.json') -Raw) -match 'prompt_router\.ps1'))

Write-Host "-- enforcement statics"
$hubSetTpl = Join-Path $engine 'templates\hub\settings.json'
$tplJsonOk = $false; try { [void](Get-Content $hubSetTpl -Raw | ConvertFrom-Json); $tplJsonOk = $true } catch { }
Ok "templates\hub\settings.json is valid JSON" $tplJsonOk
foreach ($n in @('prompt_router.ps1', 'hold_guard.ps1', 'main_agent_guard.ps1', 'reviewer_guard.ps1', 'stop_guard.ps1')) {
  $src = Get-Content (Join-Path $hookDir $n) -Raw
  Ok ($n + ': reads stdin as UTF-8 and fails open') (($src -match 'OpenStandardInput') -and ($src -match 'UTF8') -and ($src -match 'exit 0'))
  Ok ($n + ': honors $env:SONELLE_HUB or resolves the hub two levels up') (($src -match 'SONELLE_HUB') -or ($n -eq 'reviewer_guard.ps1'))
}
foreach ($n in @('prompt_router.ps1', 'hold_guard.ps1', 'main_agent_guard.ps1', 'stop_guard.ps1')) {
  $src = Get-Content (Join-Path $hookDir $n) -Raw
  Ok ($n + ': addresses the owner from hub config, no name baked into the engine') (($src -match '\$owner') -and ($src -match 'sonelle\.hub\.json') -and ($src -match "owner = 'the user'"))
}
# T2 for the v1.47 trees: templates\hub\** is copied verbatim into every hub and templates\agents\** into
# every hub AND every new project, so a stray file there spreads everywhere. Set equality, not existence.
$hubTplDir = Join-Path $engine 'templates\hub'
$hubGot  = @(Get-ChildItem $hubTplDir -Recurse -File | ForEach-Object { $_.FullName.Substring($hubTplDir.Length + 1).Replace('\', '/') } | Sort-Object)
$hubWant = @('commands/prune.md', 'hooks/hold_guard.ps1', 'hooks/main_agent_guard.ps1', 'hooks/prompt_router.ps1', 'hooks/reviewer_guard.ps1', 'hooks/stop_guard.ps1', 'settings.json') | Sort-Object
Ok "templates\hub set is exactly the known golden (T2)" (($hubGot -join '|') -eq ($hubWant -join '|'))
$agTplDir = Join-Path $engine 'templates\agents'
if (Test-Path $agTplDir) {
  $agGot  = @(Get-ChildItem $agTplDir -Recurse -File | ForEach-Object { $_.FullName.Substring($agTplDir.Length + 1).Replace('\', '/') } | Sort-Object)
  $agWant = @('implementer.md', 'reviewer.md', 'scout.md', 'verifier.md') | Sort-Object
  Ok "templates\agents set is exactly the known golden (T2)" (($agGot -join '|') -eq ($agWant -join '|'))
}
Ok "docs\ENFORCEMENT.md exists"        (Test-Path (Join-Path $engine 'docs\ENFORCEMENT.md'))
Ok "docs\HOOK_PAYLOADS.md records the T0 capture" ((Test-Path (Join-Path $engine 'docs\HOOK_PAYLOADS.md')) -and ((Get-Content (Join-Path $engine 'docs\HOOK_PAYLOADS.md') -Raw) -match 'UserPromptSubmit'))
Ok "tools\hook_probe.ps1 exists"       (Test-Path (Join-Path $engine 'tools\hook_probe.ps1'))

$env:SONELLE_HUB = $savedHub
Remove-Item $hIn, $hOut, $hErr -Force -ErrorAction SilentlyContinue
Get-ChildItem (Join-Path $env:TEMP 'sonelle') -Filter ('mode_*_' + $PID + '.json') -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem (Join-Path $env:TEMP 'sonelle') -Filter ('nudge_*_' + $PID) -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

if ($sonelleHooksStandalone) {
  Write-Host ""
  if ($script:fail -eq 0) { Write-Host ("[hooks] ALL PASS ({0} checks)" -f $script:pass) -ForegroundColor Green }
  else { Write-Host ("[hooks] {0} FAIL / {1} pass" -f $script:fail, $script:pass) -ForegroundColor Red }
  if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
  exit ([int]($script:fail -gt 0))
}
