<#
  check_pointers.ps1 - validate that the core sonelle files and every registry pointer
  resolve on disk. Catches silent renames/deletes. Hub = parent of this tools/ folder.

  Usage:  .\check_pointers.ps1 [-Hub <workspace>] [-MemoryDir <path>]
  Hub + memory dir come from sonelle.config.json (hub / memoryDir) unless overridden by params.
  Exit:   0 = all OK, 1 = at least one MISS.
#>
param([string]$Hub = '', [string]$MemoryDir = '')
$ErrorActionPreference = 'Stop'
$engine = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot '_registry.ps1')
$resolved = Get-SonelleConfig -Engine $engine -HubOverride $Hub -MemoryOverride $MemoryDir
$hub    = $resolved.Hub
$memDir  = $resolved.MemoryDir

$script:ok = 0; $script:miss = 0
function Check($label, $path) {
  if (Test-Path $path) { Write-Host ("  [OK]   {0}" -f $label) -ForegroundColor Green; $script:ok++ }
  else { Write-Host ("  [MISS] {0}  -> {1}" -f $label, $path) -ForegroundColor Red; $script:miss++ }
}

Write-Host "[check] hub files:"
Check 'CLAUDE.md'           (Join-Path $hub 'CLAUDE.md')
Check 'PROJECTS.md'         (Join-Path $hub 'PROJECTS.md')

Write-Host "[check] engine files:"
Check 'bin\sonelle.ps1'          (Join-Path $engine 'bin\sonelle.ps1')
Check 'tools\new_project.ps1' (Join-Path $engine 'tools\new_project.ps1')
Check 'tools\doctor.ps1'      (Join-Path $engine 'tools\doctor.ps1')
Check 'tools\log_lesson.ps1'  (Join-Path $engine 'tools\log_lesson.ps1')
Check 'templates dir'         (Join-Path $engine 'templates')

Write-Host "[check] registered projects (code paths + memory refs from PROJECTS.md):"
$pf = Join-Path $hub 'PROJECTS.md'
if (-not (Test-Path $pf)) {
  Write-Host ("  [MISS] PROJECTS.md not found at hub -> {0}" -f $pf) -ForegroundColor Red; $script:miss++
} else {
  $projects = Get-SonelleProjects $pf
  if ($projects.Count -eq 0) { Write-Host "  (registry empty - nothing to check)" }
  foreach ($p in $projects) {
    if (Test-SonelleCodePath $p.CodePath) { Check ("$($p.Short) code path") $p.CodePath }
  }
  # memory files referenced anywhere in the registry (resolved against $memDir from config)
  if (-not (Test-Path $memDir -PathType Container)) {
    Write-Host ("  [MISS] memory dir not found -> {0}  (set 'memoryDir' in sonelle.config.json)" -f $memDir) -ForegroundColor Red
    $script:miss++
  } else {
    $refs = [regex]::Matches((Get-Content $pf -Raw), 'project_[a-z0-9_]+\.md') | ForEach-Object { $_.Value } | Sort-Object -Unique
    foreach ($r in $refs) { Check ("memory\$r") (Join-Path $memDir $r) }
  }
}

Write-Host ""
$col = 'Green'; if ($script:miss -gt 0) { $col = 'Red' }
Write-Host ("[check] DONE: {0} OK, {1} MISS." -f $script:ok, $script:miss) -ForegroundColor $col
if ($script:miss -gt 0) { exit 1 } else { exit 0 }
