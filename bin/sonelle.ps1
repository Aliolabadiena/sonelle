<#
  sonelle.ps1 - the sonelle terminal. Claude-styled launcher: reads the grammar
  `[address,] <short>: <prompt>`, routes to the right project via PROJECTS.md, and hands
  the prompt to `claude` (Claude Code) - which runs on your Claude subscription.

  Usage:
    powershell -File bin\sonelle.ps1          start the terminal (REPL)
    powershell -File bin\sonelle.ps1 -Demo    print the banner + help, then exit (no REPL)

  Commands inside:  <short>: <prompt>   :projects   :new   :heal [short]   :team   :status   :dev   :help   :q
  Source is pure ASCII; Unicode glyphs are built at runtime via [char] codepoints.
#>
[CmdletBinding()]
param([switch]$Demo)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$hub  = $root
$orchModel = 'opus'; $orchEffort = 'xhigh'; $orchPerm = ''   # orchestrator (the session you talk to) is ALWAYS max
# optional overrides from sonelle.config.json (hub for routing; models for the orchestrator)
$cfg = Join-Path $root 'sonelle.config.json'
if (Test-Path $cfg) {
  try {
    $c = Get-Content $cfg -Raw | ConvertFrom-Json
    $h = $c.hub
    if ($h -and $h -ne '.') { if ([System.IO.Path]::IsPathRooted($h)) { $hub = $h } else { $hub = Join-Path $root $h } }
    if ($c.models.orchestrator)               { $orchModel = $c.models.orchestrator }
    if ($c.models.orchestratorEffort)         { $orchEffort = $c.models.orchestratorEffort }
    if ($c.models.orchestratorPermissionMode) { $orchPerm = $c.models.orchestratorPermissionMode }
  } catch {}
}
$psExe = (Get-Process -Id $PID).Path
. (Join-Path $root 'tools\_registry.ps1')

# --- color support: enable VT on legacy consoles; fall back to plain text ---
$useColor = -not $env:NO_COLOR
if ($useColor) {
  try {
    $vt = Add-Type -Name SonelleVT -Namespace Win32 -PassThru -ErrorAction Stop -MemberDefinition '[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int h); [DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out int m); [DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, int m);'
    $h = $vt::GetStdHandle(-11); $m = 0
    if ($vt::GetConsoleMode($h, [ref]$m)) { [void]$vt::SetConsoleMode($h, ($m -bor 4)) }   # ENABLE_VIRTUAL_TERMINAL_PROCESSING
  } catch {}
}
# --- palette (Claude: clay accent, cream text) via ANSI 24-bit; empty when no color ---
if ($useColor) {
  $E = [char]27
  $clay = "$E[38;2;204;120;92m"; $cream = "$E[38;2;235;232;222m"; $dim = "$E[38;2;140;140;140m"; $bold = "$E[1m"; $R = "$E[0m"
} else { $clay = ''; $cream = ''; $dim = ''; $bold = ''; $R = '' }
$bar = ([string][char]0x2500) * 50
$arrow = [string][char]0x25B8
$script:staged = @()   # image paths staged via :attach, consumed by the next routed prompt

function Banner {
  Clear-Host
  Write-Host ""
  Write-Host ("  {0}{1}sonelle{2}   {3}your projects, one orchestrator{2}" -f $clay, $bold, $R, $dim)
  Write-Host ("  {0}{1}{2}" -f $clay, $bar, $R)
  Write-Host ("  {0}runs on your Claude subscription via {1}claude{0}.{2}" -f $dim, $cream, $R)
  Write-Host ("  {0}type  {1}<short>: <prompt>{0}   or   {1}:help{2}" -f $dim, $cream, $R)
  Write-Host ""
}
function ShowHelp {
  Write-Host ("  {0}commands{1}" -f $bold, $R)
  Write-Host ("    {0}<short>: <prompt>{1}   open a project and run the prompt (e.g.  myproj: fix the build)" -f $cream, $R)
  Write-Host ("    {0}:projects{1}            list registered projects" -f $cream, $R)
  Write-Host ("    {0}:new{1}                 scaffold a new project" -f $cream, $R)
  Write-Host ("    {0}:heal [short]{1}        run the doctor (health/heal detector)" -f $cream, $R)
  Write-Host ("    {0}:team <proj> <lanes>{1} launch up to 5 parallel lanes (e.g. :team myproj bugs,docs)" -f $cream, $R)
  Write-Host ("    {0}:status <proj>{1}       show each lane's status" -f $cream, $R)
  Write-Host ("    {0}:dev [prompt]{1}        improve the engine itself (opens a dev session here)" -f $cream, $R)
  Write-Host ("    {0}:attach <path>{1}       stage an image for the next prompt (or inline {0}@<path>{1})" -f $cream, $R)
  Write-Host ("    {0}:clear{1}               clear staged images" -f $cream, $R)
  Write-Host ("    {0}:help{1}  {0}:q{1}            this help / quit" -f $cream, $R)
}
function ShowProjects {
  $pf = Join-Path $hub 'PROJECTS.md'
  if (-not (Test-Path $pf)) { Write-Host ("  {0}no PROJECTS.md at hub: {1}{2}" -f $dim, $hub, $R); return }
  $projs = Get-SonelleProjects $pf
  if ($projs.Count -eq 0) { Write-Host ("  {0}registry empty - type :new to create your first project.{1}" -f $dim, $R); return }
  foreach ($p in $projs) { Write-Host ("    {0}{1}{2}  {3}{4}{2}" -f $clay, $p.Short, $R, $dim, $p.Name) }
}
function ResolveCode($short) {
  $pf = Join-Path $hub 'PROJECTS.md'
  $p = (Get-SonelleProjects $pf) | Where-Object { $_.Short -eq $short } | Select-Object -First 1
  if ($p) { return $p.CodePath }
  return $null
}
function NewProject {
  $s = (Read-Host "  shortcode (a-z0-9_)").Trim()
  if (-not $s) { return }
  $n = (Read-Host "  project name").Trim()
  $p = (Read-Host "  code path").Trim()
  & $psExe -ExecutionPolicy Bypass -File (Join-Path $root 'tools\new_project.ps1') $s $n $p -Hub $hub | Out-Host
}
function Heal($short) {
  $dargs = @('-ExecutionPolicy','Bypass','-File',(Join-Path $root 'tools\doctor.ps1'))
  if ($short) { $dargs += $short }
  $dargs += @('-Hub', $hub)
  & $psExe @dargs | Out-Host
}
function Team($rest) {
  $rest = $rest.Trim(); $sp = $rest.IndexOf(' ')
  if ($sp -lt 1) { Write-Host ("  {0}usage: :team <project> <lane1,lane2,...>{1}" -f $dim, $R); return }
  $pj = $rest.Substring(0, $sp)
  $ln = ($rest.Substring($sp + 1).Trim()) -replace '\s+', ','
  & $psExe -ExecutionPolicy Bypass -File (Join-Path $root 'bin\sonelle_team.ps1') $pj -Lanes $ln -Hub $hub | Out-Host
}
function StatusLanes($pj) {
  if (-not $pj) { Write-Host ("  {0}usage: :status <project>{1}" -f $dim, $R); return }
  & $psExe -ExecutionPolicy Bypass -File (Join-Path $root 'bin\sonelle_team.ps1') $pj -Status -Hub $hub | Out-Host
}
function DevSelf($prompt) {
  $claude = Get-Command claude -ErrorAction SilentlyContinue
  if (-not $claude) {
    Write-Host ("  {0}[!] 'claude' not found on PATH - install Claude Code + log into your subscription first.{1}" -f $clay, $R)
    return
  }
  $ask = if ($prompt) { $prompt } else { 'Ask me what to improve, then propose a short plan before editing.' }
  $seed = "You are developing the sonelle ENGINE ITSELF (this repository = your current working directory). It is a PUBLIC repo with ZERO personal data.`n" +
          "Read docs\DEVELOPING.md and docs\ARCHITECTURE.md FIRST, and treat docs\DEVELOPING.md as your SOLE authority for THIS session. Claude Code auto-loads the root CLAUDE.md (the dispatcher template the engine ships) - IGNORE its dispatcher / project-routing / state-reading framing here; this session develops the engine, it does not route projects or manage a hub.`n" +
          "Honor every invariant in DEVELOPING.md: pure-ASCII PowerShell, no personal data in the repo, do NOT scaffold hub/project state (never run new_project or log_lesson at the engine root), and run tools\selftest.ps1 to ALL PASS before any commit (extend selftest for new features so the engine stays self-verifying). Everything is git-versioned, so changes are rewindable.`n`n" +
          "Task: $ask"
  Write-Host ("  {0}-> {1}dev{2}  {3}developing the engine itself{2}" -f $dim, $clay, $R, $dim)
  Write-Host ("  {0}orchestrator: {1} (effort {2}){3}" -f $dim, $orchModel, $orchEffort, $R)
  $dirty = $false
  if (Get-Command git -ErrorAction SilentlyContinue) { try { $dirty = [bool](& git -C $root status --porcelain 2>$null) } catch {} }
  if ($dirty) { Write-Host ("  {0}note: engine has uncommitted changes - commit/stash first for a clean rewind point.{1}" -f $dim, $R) }
  $cargs = @('--model', $orchModel, '--effort', $orchEffort); if ($orchPerm) { $cargs += @('--permission-mode', $orchPerm) }
  Push-Location $root
  try { & claude @cargs $seed } finally { Pop-Location }
  # invariant #4 guard: the engine must stay clean of hub state - warn if a session left any behind
  $junk = @(Get-ChildItem $root -Filter '*_TODO.txt' -File -ErrorAction SilentlyContinue) + @(Get-ChildItem $root -Filter '_*_run_STATUS.md' -File -ErrorAction SilentlyContinue)
  if ($junk.Count -gt 0 -or (Test-Path (Join-Path $root 'memory'))) {
    Write-Host ("  {0}[!] hub-state (TODO/ledger/memory) detected in the engine root - it must stay clean; move it to your hub or delete it.{1}" -f $clay, $R)
  }
}
function Route($short, $prompt, $images) {
  $code = ResolveCode $short
  if (-not $code) {
    Write-Host ("  {0}'{1}' is not in the registry.{2}" -f $clay, $short, $R)
    if ((Read-Host "  create new project '$short'? (y/N)") -match '^(y|Y)') { NewProject }
    return
  }
  if ($code -notmatch '^[-(]' -and -not (Test-Path $code)) { Write-Host ("  {0}[warn] code path missing: {1}{2}" -f $clay, $code, $R) }
  $claude = Get-Command claude -ErrorAction SilentlyContinue
  if (-not $claude) {
    Write-Host ("  {0}[!] 'claude' not found on PATH. Install Claude Code and log into your subscription,{1}" -f $clay, $R)
    Write-Host ("  {0}    then this terminal will hand prompts to it. (https://claude.com/claude-code){1}" -f $dim, $R)
    return
  }
  $finalPrompt = $prompt
  if ($images -and $images.Count -gt 0) {
    $finalPrompt = $prompt + "`n`nAttached image(s) - please read them:`n" + (($images | ForEach-Object { " - $_" }) -join "`n")
    Write-Host ("  {0}+ {1} image(s) attached{2}" -f $dim, $images.Count, $R)
  }
  Write-Host ("  {0}-> {1}{2}{3}  {4}{5}{3}" -f $dim, $clay, $short, $R, $dim, $code)
  Write-Host ("  {0}orchestrator: {1} (effort {2})  |  prompt: {3}{4}" -f $dim, $orchModel, $orchEffort, ($finalPrompt -replace "`n", " / "), $R)
  $cargs = @('--model', $orchModel, '--effort', $orchEffort); if ($orchPerm) { $cargs += @('--permission-mode', $orchPerm) }
  if ($code -notmatch '^[-(]' -and (Test-Path $code)) { Push-Location $code } else { Push-Location $root }
  try { & claude @cargs $finalPrompt } finally { Pop-Location }
  $script:staged = @()   # staged images consumed
}

Banner
ShowHelp
if ($Demo) { Write-Host ""; Write-Host ("  {0}(demo mode - exiting before REPL){1}" -f $dim, $R); return }
Write-Host ""

while ($true) {
  Write-Host -NoNewline ("{0}sonelle {1}{2} " -f $clay, $arrow, $R)
  $in = Read-Host
  if ($null -eq $in) { break }
  $t = $in.Trim()
  if (-not $t) { continue }
  if ($t -match '^:(q|quit|exit)$') { break }
  elseif ($t -eq ':help') { ShowHelp; continue }
  elseif ($t -eq ':projects') { ShowProjects; continue }
  elseif ($t -eq ':new') { NewProject; continue }
  elseif ($t -match '^:heal\s*(.*)$') { Heal ($Matches[1].Trim()); continue }
  elseif ($t -match '^:team\s+(.+)$') { Team $Matches[1]; continue }
  elseif ($t -match '^:status\s*(.*)$') { StatusLanes ($Matches[1].Trim()); continue }
  elseif ($t -match '^:dev\b\s*(.*)$') { DevSelf ($Matches[1].Trim()); continue }
  elseif ($t -match '^:attach\s+(.+)$') {
    $ip = $Matches[1].Trim().Trim('"')
    if (Test-Path $ip) { $script:staged += (Resolve-Path $ip).Path; Write-Host ("  {0}staged ({1} total): {2}{3}" -f $dim, $script:staged.Count, $ip, $R) }
    else { Write-Host ("  {0}[!] not found: {1}{2}" -f $clay, $ip, $R) }
    continue
  }
  elseif ($t -eq ':clear') { $script:staged = @(); Write-Host ("  {0}staged images cleared{1}" -f $dim, $R); continue }
  else {
    $bodyText = $t
    # strip a leading "address," ONLY when what follows is a real "<short>: ..." (don't mangle prose with commas)
    if ($bodyText -match '^[A-Za-z0-9 _-]+,\s*([a-z0-9_]+\s*:.+)$') { $bodyText = $Matches[1] }
    # pull out inline @<path> images, removing ONLY tokens that are real files (leave emails/@handles/decorators alone)
    $imgs = @() + $script:staged
    foreach ($mm in [regex]::Matches($bodyText, '@"([^"]+)"|@(\S+)')) {
      $p = if ($mm.Groups[1].Value) { $mm.Groups[1].Value } else { $mm.Groups[2].Value }
      if (Test-Path $p) { $imgs += (Resolve-Path $p).Path; $bodyText = $bodyText.Replace($mm.Value, '') }
    }
    $bodyText = $bodyText.Trim()
    if ($bodyText -match '^([a-z0-9_]+)\s*:\s*(.+)$') { Route $Matches[1].ToLower() $Matches[2] $imgs }
    else { Write-Host ("  {0}? use  {1}<short>: <prompt>{0}  (e.g.  myproj: fix the build){2}" -f $dim, $cream, $R) }
  }
}
Write-Host ("{0}  bye.{1}" -f $dim, $R)
