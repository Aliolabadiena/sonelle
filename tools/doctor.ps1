<#
  doctor.ps1 - health check / HEAL detector. Reports problems; Claude reads the report,
  fixes each FAIL, and re-runs until green (see docs\HEAL.md). doctor DETECTS; Claude HEALS.

  Usage:
    .\doctor.ps1            check the whole workspace + all projects
    .\doctor.ps1 myproj     focus one project

  Per-project hook: if <code path>\sonelle.check.ps1 exists, doctor runs it (exit 0 = healthy).
  Put a project's real checks there (tests, analyze, build smoke, etc.).

  Exit: 0 = healthy, 1 = at least one FAIL.
#>
param([string]$Short = '', [string]$Hub = '')

$ErrorActionPreference = 'Stop'
$hub = if ($Hub) { $Hub } else { Split-Path $PSScriptRoot -Parent }
$ps  = (Get-Process -Id $PID).Path  # this powershell exe, for child invocations
. (Join-Path $PSScriptRoot '_registry.ps1')
$fails = 0
$checked = 0
function Section($t) { Write-Host ""; Write-Host ("== {0} ==" -f $t) -ForegroundColor Cyan }
function Result($label, $ok, $detail) {
  if ($ok) { Write-Host ("  [PASS] {0}" -f $label) -ForegroundColor Green }
  else { Write-Host ("  [FAIL] {0} {1}" -f $label, $detail) -ForegroundColor Red; $script:fails++ }
}

Section "environment"
Write-Host ("  [info] PowerShell {0}" -f $PSVersionTable.PSVersion)
if (Get-Command claude -ErrorAction SilentlyContinue) { Write-Host "  [PASS] claude on PATH" -ForegroundColor Green }
else { Write-Host "  [warn] claude NOT on PATH - the terminal cannot hand off until Claude Code is installed + on PATH" -ForegroundColor Yellow }

Section "pointers"
& $ps -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'check_pointers.ps1') -Hub $hub | Out-Null
Result "registry pointers resolve" ($LASTEXITCODE -eq 0) "(run check_pointers.ps1 for detail)"

Section "git (hub)"
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Write-Host "  [info] git not on PATH - skipping git check" -ForegroundColor DarkGray
} elseif (Test-Path (Join-Path $hub '.git')) {
  $dirty = git -C $hub status --porcelain
  if ([string]::IsNullOrWhiteSpace($dirty)) { Write-Host "  [PASS] working tree clean" -ForegroundColor Green }
  else { $n = ($dirty -split "`n").Count; Write-Host ("  [warn] {0} uncommitted change(s) - back up when done" -f $n) -ForegroundColor Yellow }
} else { Write-Host "  [info] hub is not a git repo (no rewind/backup here)" -ForegroundColor DarkGray }

Section "projects"
$pf = Join-Path $hub 'PROJECTS.md'
$any = $false
if (-not (Test-Path $pf)) {
  Result "PROJECTS.md exists" $false "-> $pf"
} else {
  foreach ($p in (Get-SonelleProjects $pf)) {
    if ($Short -and $p.Short -ne $Short) { continue }
    $any = $true
    $code = $p.CodePath
    Write-Host ("  - {0} ({1})" -f $p.Short, $code)
    if ($code -and $code -notmatch '^[-(]') {
      Result "    code path exists" (Test-Path $code) "-> $code"
      $checked++
      $hook = Join-Path $code 'sonelle.check.ps1'
      if (Test-Path $hook) {
        & $ps -ExecutionPolicy Bypass -File $hook | Out-Host
        Result "    project check (sonelle.check.ps1)" ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"
        $checked++
      } else {
        Write-Host "    [info] no sonelle.check.ps1 (add one to define this project's health checks)" -ForegroundColor DarkGray
      }
    }
  }
}
if (-not $any) { Write-Host "  (no matching projects)" -ForegroundColor DarkGray }

Write-Host ""
if ($fails -gt 0) { Write-Host ("[doctor] {0} FAIL(s) - heal: diagnose each, fix, re-run (docs\HEAL.md)." -f $fails) -ForegroundColor Red; exit 1 }
elseif ($checked -eq 0) { Write-Host "[doctor] NOTHING CHECKED (empty registry / no code paths / no sonelle.check.ps1) - NOT a real all-clear." -ForegroundColor Yellow; exit 0 }
else { Write-Host ("[doctor] HEALTHY ({0} check(s), 0 fails)." -f $checked) -ForegroundColor Green; exit 0 }
