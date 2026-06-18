<#
  doctor.ps1 - health check / HEAL detector. Reports problems; Claude reads the report,
  fixes each FAIL, and re-runs until green (see docs\HEAL.md). doctor DETECTS; Claude HEALS.

  Usage:
    .\doctor.ps1            check the whole workspace + all projects
    .\doctor.ps1 myproj     focus one project

  Per-project hook: if <code path>\luna.check.ps1 exists, doctor runs it (exit 0 = healthy).
  Put a project's real checks there (tests, analyze, build smoke, etc.).

  Exit: 0 = healthy, 1 = at least one FAIL.
#>
param([string]$Short = '', [string]$Hub = '')

$ErrorActionPreference = 'Stop'
$hub = if ($Hub) { $Hub } else { Split-Path $PSScriptRoot -Parent }
$ps  = (Get-Process -Id $PID).Path  # this powershell exe, for child invocations
$fails = 0
function Section($t) { Write-Host ""; Write-Host ("== {0} ==" -f $t) -ForegroundColor Cyan }
function Result($label, $ok, $detail) {
  if ($ok) { Write-Host ("  [PASS] {0}" -f $label) -ForegroundColor Green }
  else { Write-Host ("  [FAIL] {0} {1}" -f $label, $detail) -ForegroundColor Red; $script:fails++ }
}

Section "pointers"
& $ps -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'check_pointers.ps1') -Hub $hub | Out-Null
Result "registry pointers resolve" ($LASTEXITCODE -eq 0) "(run check_pointers.ps1 for detail)"

Section "git (hub)"
if (Test-Path (Join-Path $hub '.git')) {
  $dirty = git -C $hub status --porcelain
  if ([string]::IsNullOrWhiteSpace($dirty)) { Write-Host "  [PASS] working tree clean" -ForegroundColor Green }
  else { $n = ($dirty -split "`n").Count; Write-Host ("  [warn] {0} uncommitted change(s) - back up when done" -f $n) -ForegroundColor Yellow }
} else { Write-Host "  [info] hub is not a git repo (no rewind/backup here)" -ForegroundColor DarkGray }

Section "projects"
$pf = Join-Path $hub 'PROJECTS.md'
$txt = Get-Content $pf -Raw
$rows = [regex]::Matches($txt, '(?m)^\|\s*([a-z0-9_]+)\s*\|\s*([^|]*)\|\s*([^|]*)\|')
$any = $false
foreach ($m in $rows) {
  $s = $m.Groups[1].Value
  if ($s -eq 'Shortcode') { continue }
  if ($Short -and $s -ne $Short) { continue }
  $any = $true
  $code = $m.Groups[3].Value.Trim()
  Write-Host ("  - {0} ({1})" -f $s, $code)
  if ($code -and $code -notmatch '^[-(]') {
    Result "    code path exists" (Test-Path $code) "-> $code"
    $hook = Join-Path $code 'luna.check.ps1'
    if (Test-Path $hook) {
      & $ps -ExecutionPolicy Bypass -File $hook | Out-Host
      Result "    project check (luna.check.ps1)" ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"
    } else {
      Write-Host "    [info] no luna.check.ps1 (add one to define this project's health checks)" -ForegroundColor DarkGray
    }
  }
}
if (-not $any) { Write-Host "  (no matching projects)" -ForegroundColor DarkGray }

Write-Host ""
if ($fails -eq 0) { Write-Host "[doctor] HEALTHY (0 fails)." -ForegroundColor Green; exit 0 }
else { Write-Host ("[doctor] {0} FAIL(s) - heal: diagnose each, fix, re-run (docs\HEAL.md)." -f $fails) -ForegroundColor Red; exit 1 }
