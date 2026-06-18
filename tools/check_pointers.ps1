<#
  check_pointers.ps1 - validate that the core luna files and every registry pointer
  resolve on disk. Catches silent renames/deletes. Hub = parent of this tools/ folder.

  Usage:  .\check_pointers.ps1
  Exit:   0 = all OK, 1 = at least one MISS.
#>
$ErrorActionPreference = 'Stop'
$hub    = Split-Path $PSScriptRoot -Parent
$memDir = Join-Path $hub 'memory'

$script:ok = 0; $script:miss = 0
function Check($label, $path) {
  if (Test-Path $path) { Write-Host ("  [OK]   {0}" -f $label) -ForegroundColor Green; $script:ok++ }
  else { Write-Host ("  [MISS] {0}  -> {1}" -f $label, $path) -ForegroundColor Red; $script:miss++ }
}

Write-Host "[check] core engine files:"
Check 'CLAUDE.md'           (Join-Path $hub 'CLAUDE.md')
Check 'PROJECTS.md'         (Join-Path $hub 'PROJECTS.md')
Check 'README.md'           (Join-Path $hub 'README.md')
Check 'bin\luna.ps1'        (Join-Path $hub 'bin\luna.ps1')
Check 'tools\new_project.ps1' (Join-Path $hub 'tools\new_project.ps1')
Check 'tools\doctor.ps1'    (Join-Path $hub 'tools\doctor.ps1')
Check 'templates dir'       (Join-Path $hub 'templates')

Write-Host "[check] registered projects (code paths + memory refs from PROJECTS.md):"
$pf = Join-Path $hub 'PROJECTS.md'
$txt = Get-Content $pf -Raw
$rows = [regex]::Matches($txt, '(?m)^\|\s*([a-z0-9_]+)\s*\|([^\r\n]*)$')
if ($rows.Count -eq 0) { Write-Host "  (registry empty - nothing to check)" }
foreach ($m in $rows) {
  $short = $m.Groups[1].Value
  if ($short -eq 'Shortcode') { continue }
  $cells = $m.Groups[2].Value.Split('|')
  if ($cells.Count -ge 2) {
    $codePath = $cells[1].Trim()
    if ($codePath -and $codePath -notmatch '^[-(]' ) { Check ("$short code path") $codePath }
  }
}
# memory files referenced anywhere in the registry
$refs = [regex]::Matches($txt, 'project_[a-z0-9_]+\.md') | ForEach-Object { $_.Value } | Sort-Object -Unique
foreach ($r in $refs) { Check ("memory\$r") (Join-Path $memDir $r) }

Write-Host ""
$col = 'Green'; if ($script:miss -gt 0) { $col = 'Red' }
Write-Host ("[check] DONE: {0} OK, {1} MISS." -f $script:ok, $script:miss) -ForegroundColor $col
if ($script:miss -gt 0) { exit 1 } else { exit 0 }
