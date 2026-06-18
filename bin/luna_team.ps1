<#
  luna_team.ps1 - run up to 5 parallel luna instances ("lanes") on one project, each scoped to a
  disjoint workstream (e.g. bugs / concepts / website). Each lane = its own `claude` session in the
  project dir, seeded to own ONLY its lane and coordinate via a shared board at <code>\.luna\lanes\.
  Sessions do NOT share live memory - they coordinate via those files + disjoint ownership.

  Usage:
    luna_team.ps1 <project> -Lanes bugs,concepts,website     launch lanes (Windows Terminal tabs if wt, else windows)
    luna_team.ps1 <project> -Lanes bugs,concepts -DryRun     write the board + start scripts, do NOT launch
    luna_team.ps1 <project> -Status                          show each lane's status

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
$cfg = Join-Path $engine 'luna.config.json'
if (-not $Hub -and (Test-Path $cfg)) {
  try { $h = (Get-Content $cfg -Raw | ConvertFrom-Json).hub
        if ($h -and $h -ne '.') { $hub = if ([System.IO.Path]::IsPathRooted($h)) { $h } else { Join-Path $engine $h } } } catch {}
}
. (Join-Path $engine 'tools\_registry.ps1')

$pf = Join-Path $hub 'PROJECTS.md'
$proj = (Get-LunaProjects $pf) | Where-Object { $_.Short -eq $Project.ToLower() } | Select-Object -First 1
if (-not $proj) { Write-Host "[X] project '$Project' not in $pf" -ForegroundColor Red; exit 1 }
$code = $proj.CodePath
if ($code -match '^[-(]' -or -not (Test-Path $code)) { Write-Host "[X] code path missing/NA: $code" -ForegroundColor Red; exit 1 }
$lanesDir = Join-Path $code '.luna\lanes'

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

if (-not $Lanes -or $Lanes.Count -eq 0) { Write-Host "[X] give -Lanes (e.g. -Lanes bugs,concepts,website)" -ForegroundColor Red; exit 1 }
$Lanes = @($Lanes | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
foreach ($l in $Lanes) { if ($l -notmatch '^[a-z0-9_-]+$') { Write-Host "[X] bad lane name '$l' (use a-z 0-9 _ -)." -ForegroundColor Red; exit 1 } }
if (($Lanes | Sort-Object -Unique).Count -ne $Lanes.Count) { Write-Host "[X] duplicate lane names." -ForegroundColor Red; exit 1 }
if ($Lanes.Count -gt 5) { Write-Host "[X] max 5 lanes (got $($Lanes.Count))." -ForegroundColor Red; exit 1 }
if ($Lanes.Count -gt 3) { Write-Host "[!] $($Lanes.Count) parallel sessions ~= $($Lanes.Count)x your Claude usage - watch rate limits." -ForegroundColor Yellow }

if (-not (Test-Path $lanesDir)) { New-Item -ItemType Directory -Path $lanesDir -Force | Out-Null }
$date = (Get-Date).ToString('yyyy-MM-dd HH:mm')
$wt = Get-Command wt -ErrorAction SilentlyContinue
function Wr($p, $t) { [System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false))) }

$wtTabs = @()
foreach ($l in $Lanes) {
  $others = ($Lanes | Where-Object { $_ -ne $l }) -join ', '
  $statusFile = Join-Path $lanesDir ($l + '.md')
  Wr $statusFile "# lane: $l ($Project)`r`nstarted: $date`r`nstatus: active`r`nowns: (declare files/dirs this lane edits)`r`nother lanes - DO NOT touch their files: $others`r`n`r`n## log`r`n- $date started`r`n"
  $seed = "You are luna lane '$l' for project '$Project'. You own ONLY the '$l' workstream. The other lanes are: $others - read .luna/lanes/ and DO NOT edit their files (keep ownership disjoint; this project may have no git merge safety). Update .luna/lanes/$l.md as you work. Tell me this lane's task and I will work only within it."
  $startPs = Join-Path $lanesDir ($l + '.start.ps1')
  Wr $startPs "Set-Location -LiteralPath '$code'`r`nclaude @'`r`n$seed`r`n'@`r`n"
  $wtTabs += 'new-tab --title "luna:' + $Project + ':' + $l + '" -d "' + $code + '" powershell -NoExit -ExecutionPolicy Bypass -File "' + $startPs + '"'
  Write-Host "[+] lane '$l' -> .luna\lanes\$l.md (+ start script)"
}

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
  Write-Host "[!] 'claude' not on PATH - lanes scaffolded, but install Claude Code + login to launch." -ForegroundColor Yellow
}
if ($DryRun) { Write-Host "[dry-run] board + start scripts written under $lanesDir (not launched)."; exit 0 }

Write-Host "launching $($Lanes.Count) lane(s)..."
if ($wt) {
  Start-Process $wt.Source -ArgumentList ($wtTabs -join ' ; ')
} else {
  foreach ($l in $Lanes) {
    Start-Process powershell -ArgumentList @('-NoExit', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $lanesDir ($l + '.start.ps1')))
  }
}
Write-Host "launched. check status: luna_team.ps1 $Project -Status"
exit 0
