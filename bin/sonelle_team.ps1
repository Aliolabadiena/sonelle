<#
  sonelle_team.ps1 - run up to 5 parallel sonelle instances ("lanes") on one project, each scoped to a
  disjoint workstream (e.g. bugs / concepts / website). Each lane = its own `claude` session in the
  project dir, seeded to own ONLY its lane and coordinate via a shared board at <code>\.sonelle\lanes\.
  Sessions do NOT share live memory - they coordinate via those files + disjoint ownership.

  Usage:
    sonelle_team.ps1 <project> -Lanes bugs,concepts,website     launch lanes (Windows Terminal tabs if wt, else windows)
    sonelle_team.ps1 <project> -Lanes bugs,concepts -DryRun     write the board + start scripts, do NOT launch
    sonelle_team.ps1 <project> -Status                          show each lane's status

  CAVEAT: N parallel sessions ~= Nx your Claude subscription usage (watch rate limits). Keep lanes DISJOINT.
#>
param(
  [Parameter(Mandatory = $true, Position = 0)][string]$Project,
  [Parameter(Position = 1)][string[]]$Lanes,
  [string]$Hub = '',
  [switch]$Status,
  [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$engine = Split-Path $PSScriptRoot -Parent
$hub = if ($Hub) { $Hub } else { $engine }
$laneModel = 'opus'; $laneEffort = 'high'; $lanePerm = 'acceptEdits'   # worker defaults; per-lane override via name=model:effort
$cfg = Join-Path $engine 'sonelle.config.json'
if (Test-Path $cfg) {
  try {
    $c = Get-Content $cfg -Raw | ConvertFrom-Json
    if (-not $Hub -and $c.hub -and $c.hub -ne '.') { $hub = if ([System.IO.Path]::IsPathRooted($c.hub)) { $c.hub } else { Join-Path $engine $c.hub } }
    if ($c.models.laneDefault)        { $laneModel = $c.models.laneDefault }
    if ($c.models.laneEffort)         { $laneEffort = $c.models.laneEffort }
    if ($c.models.lanePermissionMode) { $lanePerm = $c.models.lanePermissionMode }
  } catch {}
}
. (Join-Path $engine 'tools\_registry.ps1')

$pf = Join-Path $hub 'PROJECTS.md'
$proj = (Get-SonelleProjects $pf) | Where-Object { $_.Short -eq $Project.ToLower() } | Select-Object -First 1
if (-not $proj) { Write-Host "[X] project '$Project' not in $pf" -ForegroundColor Red; exit 1 }
$code = $proj.CodePath
if ($code -match '^[-(]' -or -not (Test-Path $code)) { Write-Host "[X] code path missing/NA: $code" -ForegroundColor Red; exit 1 }
$lanesDir = Join-Path $code '.sonelle\lanes'

if ($Status) {
  if (-not (Test-Path $lanesDir)) { Write-Host "no lanes yet for '$Project'."; exit 0 }
  Write-Host "== lanes for $Project =="
  $found = $false
  foreach ($f in (Get-ChildItem $lanesDir -Filter *.md -ErrorAction SilentlyContinue)) {
    $found = $true
    Write-Host ("  - {0}" -f $f.BaseName) -ForegroundColor Cyan
    (Get-Content $f.FullName | Select-Object -First 5) | ForEach-Object { Write-Host "      $_" }
  }
  if (-not $found) { Write-Host "  (none)" }
  exit 0
}

if (-not $Lanes -or $Lanes.Count -eq 0) { Write-Host "[X] give -Lanes (e.g. -Lanes bugs,concepts,website  or  bugs=opus,triage=haiku:medium)" -ForegroundColor Red; exit 1 }
$specs = @()
foreach ($entry in ($Lanes | ForEach-Object { $_ -split ',' })) {
  $e = $entry.Trim(); if (-not $e) { continue }
  $eq = $e.Split('='); $name = $eq[0].Trim().ToLower(); $m = $laneModel; $ef = $laneEffort
  if ($eq.Count -gt 1 -and $eq[1].Trim()) { $me = $eq[1].Trim().Split(':'); $m = $me[0].Trim(); if ($me.Count -gt 1 -and $me[1].Trim()) { $ef = $me[1].Trim().ToLower() } }
  if ($name -notmatch '^[a-z0-9_-]+$') { Write-Host "[X] bad lane name '$name' (use a-z 0-9 _ -)." -ForegroundColor Red; exit 1 }
  if (@('low', 'medium', 'high', 'xhigh') -notcontains $ef) { Write-Host "[X] bad effort '$ef' for lane '$name' (low|medium|high|xhigh)." -ForegroundColor Red; exit 1 }
  $specs += [pscustomobject]@{ Name = $name; Model = $m; Effort = $ef }
}
$names = @($specs | ForEach-Object { $_.Name })
if (($names | Sort-Object -Unique).Count -ne $names.Count) { Write-Host "[X] duplicate lane names." -ForegroundColor Red; exit 1 }
if ($specs.Count -gt 5) { Write-Host "[X] max 5 lanes (got $($specs.Count))." -ForegroundColor Red; exit 1 }
if ($specs.Count -gt 3) { Write-Host "[!] $($specs.Count) parallel sessions ~= $($specs.Count)x your Claude usage - watch rate limits." -ForegroundColor Yellow }

if (-not (Test-Path $lanesDir)) { New-Item -ItemType Directory -Path $lanesDir -Force | Out-Null }
$date = (Get-Date).ToString('yyyy-MM-dd HH:mm')
$wt = Get-Command wt -ErrorAction SilentlyContinue
function Wr($p, $t) { [System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false))) }

$wtTabs = @()
foreach ($s in $specs) {
  $l = $s.Name
  $others = ($names | Where-Object { $_ -ne $l }) -join ', '
  $statusFile = Join-Path $lanesDir ($l + '.md')
  Wr $statusFile "# lane: $l ($Project)`r`nmodel: $($s.Model) (effort $($s.Effort))`r`nstarted: $date`r`nstatus: active`r`nowns: (declare files/dirs this lane edits)`r`nother lanes - DO NOT touch their files: $others`r`n`r`n## log`r`n- $date started`r`n"
  $seed = "You are sonelle lane '$l' for project '$Project'. You own ONLY the '$l' workstream. The other lanes are: $others - read .sonelle/lanes/ and DO NOT edit their files (keep ownership disjoint; this project may have no git merge safety). Update .sonelle/lanes/$l.md as you work. Tell me this lane's task and I will work only within it."
  $startPs = Join-Path $lanesDir ($l + '.start.ps1')
  Wr $startPs "Set-Location -LiteralPath '$code'`r`nclaude --model $($s.Model) --effort $($s.Effort) --permission-mode $lanePerm @'`r`n$seed`r`n'@`r`n"
  $wtTabs += 'new-tab --title "sonelle:' + $Project + ':' + $l + '" -d "' + $code + '" powershell -NoExit -ExecutionPolicy Bypass -File "' + $startPs + '"'
  Write-Host ("[+] lane '{0}' ({1}/{2}) -> .sonelle\lanes\{0}.md (+ start script)" -f $l, $s.Model, $s.Effort)
}

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
  Write-Host "[!] 'claude' not on PATH - lanes scaffolded, but install Claude Code + login to launch." -ForegroundColor Yellow
}
if ($DryRun) { Write-Host "[dry-run] board + start scripts written under $lanesDir (not launched)."; exit 0 }

Write-Host "launching $($specs.Count) lane(s)..."
if ($wt) {
  Start-Process $wt.Source -ArgumentList ($wtTabs -join ' ; ')
} else {
  foreach ($s in $specs) {
    Start-Process powershell -ArgumentList @('-NoExit', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $lanesDir ($s.Name + '.start.ps1')))
  }
}
Write-Host "launched. check status: sonelle_team.ps1 $Project -Status"
exit 0
