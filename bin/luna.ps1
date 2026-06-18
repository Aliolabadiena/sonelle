<#
  luna.ps1 - the luna terminal. Claude-styled launcher: reads the grammar
  `[address,] <short>: <prompt>`, routes to the right project via PROJECTS.md, and hands
  the prompt to `claude` (Claude Code) - which runs on your Claude subscription.

  Usage:
    powershell -File bin\luna.ps1          start the terminal (REPL)
    powershell -File bin\luna.ps1 -Demo    print the banner + help, then exit (no REPL)

  Commands inside:  <short>: <prompt>   :projects   :new   :heal [short]   :help   :q
  Source is pure ASCII; Unicode glyphs are built at runtime via [char] codepoints.
#>
[CmdletBinding()]
param([switch]$Demo)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$hub  = $root
# optional: routing hub override from luna.config.json (advanced; :new always targets $root)
$cfg = Join-Path $root 'luna.config.json'
if (Test-Path $cfg) {
  try {
    $h = (Get-Content $cfg -Raw | ConvertFrom-Json).hub
    if ($h -and $h -ne '.') { if ([System.IO.Path]::IsPathRooted($h)) { $hub = $h } else { $hub = Join-Path $root $h } }
  } catch {}
}
$psExe = (Get-Process -Id $PID).Path

# --- palette (Claude: clay accent, cream text) via ANSI 24-bit ---
$E = [char]27
$clay = "$E[38;2;204;120;92m"; $cream = "$E[38;2;235;232;222m"; $dim = "$E[38;2;140;140;140m"
$bold = "$E[1m"; $R = "$E[0m"
$bar = ([string][char]0x2500) * 50
$arrow = [string][char]0x25B8
$script:staged = @()   # image paths staged via :attach, consumed by the next routed prompt

function Banner {
  Clear-Host
  Write-Host ""
  Write-Host ("  {0}{1}luna{2}   {3}your projects, one orchestrator{2}" -f $clay, $bold, $R, $dim)
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
  Write-Host ("    {0}:attach <path>{1}       stage an image for the next prompt (or inline {0}@<path>{1})" -f $cream, $R)
  Write-Host ("    {0}:clear{1}               clear staged images" -f $cream, $R)
  Write-Host ("    {0}:help{1}  {0}:q{1}            this help / quit" -f $cream, $R)
}
function ShowProjects {
  $pf = Join-Path $hub 'PROJECTS.md'
  if (-not (Test-Path $pf)) { Write-Host ("  {0}no PROJECTS.md at hub: {1}{2}" -f $dim, $hub, $R); return }
  $rows = [regex]::Matches((Get-Content $pf -Raw), '(?m)^\|\s*([a-z0-9_]+)\s*\|\s*([^|]*)\|')
  $found = $false
  foreach ($m in $rows) { if ($m.Groups[1].Value -eq 'Shortcode') { continue }
    $found = $true; Write-Host ("    {0}{1}{2}  {3}{4}{2}" -f $clay, $m.Groups[1].Value, $R, $dim, $m.Groups[2].Value.Trim()) }
  if (-not $found) { Write-Host ("  {0}registry empty - type :new to create your first project.{1}" -f $dim, $R) }
}
function ResolveCode($short) {
  $pf = Join-Path $hub 'PROJECTS.md'
  if (-not (Test-Path $pf)) { return $null }
  $m = [regex]::Match((Get-Content $pf -Raw), ('(?m)^\|\s*' + [regex]::Escape($short) + '\s*\|\s*[^|]*\|\s*([^|]*)\|'))
  if ($m.Success) { return $m.Groups[1].Value.Trim() }
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
  if ($code -notmatch '^[-(]' -and (Test-Path $code)) { Push-Location $code } else { Push-Location $root }
  try { & claude $finalPrompt } finally { Pop-Location }
  $script:staged = @()   # staged images consumed
}

Banner
ShowHelp
if ($Demo) { Write-Host ""; Write-Host ("  {0}(demo mode - exiting before REPL){1}" -f $dim, $R); return }
Write-Host ""

while ($true) {
  Write-Host -NoNewline ("{0}luna {1}{2} " -f $clay, $arrow, $R)
  $in = Read-Host
  if ($null -eq $in) { break }
  $t = $in.Trim()
  if (-not $t) { continue }
  if ($t -match '^:(q|quit|exit)$') { break }
  elseif ($t -eq ':help') { ShowHelp; continue }
  elseif ($t -eq ':projects') { ShowProjects; continue }
  elseif ($t -eq ':new') { NewProject; continue }
  elseif ($t -match '^:heal\s*(.*)$') { Heal ($Matches[1].Trim()); continue }
  elseif ($t -match '^:attach\s+(.+)$') {
    $ip = $Matches[1].Trim().Trim('"')
    if (Test-Path $ip) { $script:staged += (Resolve-Path $ip).Path; Write-Host ("  {0}staged ({1} total): {2}{3}" -f $dim, $script:staged.Count, $ip, $R) }
    else { Write-Host ("  {0}[!] not found: {1}{2}" -f $clay, $ip, $R) }
    continue
  }
  elseif ($t -eq ':clear') { $script:staged = @(); Write-Host ("  {0}staged images cleared{1}" -f $dim, $R); continue }
  else {
    $bodyText = $t
    if ($bodyText -match '^[^,:]+,\s*(.+)$') { $bodyText = $Matches[1] }   # strip leading "address,"
    # collect inline @<path> images, then strip them from the prompt text
    $imgs = @() + $script:staged
    foreach ($mm in [regex]::Matches($bodyText, '@"([^"]+)"|@(\S+)')) {
      $p = if ($mm.Groups[1].Value) { $mm.Groups[1].Value } else { $mm.Groups[2].Value }
      if (Test-Path $p) { $imgs += (Resolve-Path $p).Path } else { Write-Host ("  {0}[!] image not found: {1}{2}" -f $clay, $p, $R) }
    }
    $bodyText = ([regex]::Replace($bodyText, '@"[^"]+"|@\S+', '')).Trim()
    if ($bodyText -match '^([a-z0-9_]+)\s*:\s*(.+)$') { Route $Matches[1] $Matches[2] $imgs }
    else { Write-Host ("  {0}? use  {1}<short>: <prompt>{0}  (e.g.  myproj: fix the build){2}" -f $dim, $cream, $R) }
  }
}
Write-Host ("{0}  bye.{1}" -f $dim, $R)
