<#
  log_lesson.ps1 - SELF-IMPROVE capture. Persist a lesson (gotcha / feedback / fact) so the next
  session recalls it.

  By DEFAULT a lesson is personal / per-project -> it goes to the gitignored hub `memory\` (Hub =
  parent of tools\, or -Hub <path>). Pass -Shared for a GENERIC, cross-project lesson with NO
  personal data -> it ships IN the engine at `knowledge\` (public, pure ASCII) and is linked from
  knowledge\INDEX.md, so a fresh clone of sonelle already knows it.

  Usage:
    .\log_lesson.ps1 -Slug build-needs-keys -Type gotcha `
      -Desc "Always build with --dart-define keys" `
      -Body "A keyless build runs offline and looks like data loss." `
      -Why "Offline build seeds ~20 rows" -How "Always pass the keys; verify len."

    .\log_lesson.ps1 -Shared -Slug ps-commit-heredoc -Type reference `
      -Desc "PS 5.1 git commit -m heredoc fails" -Body "..." -How "Use git commit -F <tempfile>."
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Slug,
  [Parameter(Mandatory = $true)][string]$Desc,
  [Parameter(Mandatory = $true)][string]$Body,
  [ValidateSet('gotcha','feedback','project','reference')][string]$Type = 'gotcha',
  [string]$Why = '',
  [string]$How = '',
  [string]$Hub = '',
  [switch]$Shared
)
$ErrorActionPreference = 'Stop'
$engine = Split-Path $PSScriptRoot -Parent
$tpl    = Join-Path $engine 'templates\lesson.template.md'

if ($Shared) {
  # GENERIC, cross-project lesson -> ships IN the engine (public; keep it ASCII + personal-data-free).
  $outDir    = Join-Path $engine 'knowledge'
  $idxFile   = Join-Path $outDir 'INDEX.md'
  $idxHeader = "# sonelle knowledge - reusable lessons (ships with the engine)"
} else {
  # personal / per-project lesson -> stays in the gitignored hub memory.
  $hub       = if ($Hub) { $Hub } else { $engine }
  $outDir    = Join-Path $hub 'memory'
  $idxFile   = Join-Path $outDir 'MEMORY.md'
  $idxHeader = "# Memory index"
}
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
if (-not (Test-Path $idxFile)) { [System.IO.File]::WriteAllText($idxFile, $idxHeader, (New-Object System.Text.UTF8Encoding($false))) }

if ($Slug -notmatch '^[a-z0-9_-]+$') { Write-Host "[X] Slug must be a-z 0-9 _ - only." -ForegroundColor Red; exit 1 }
$file = Join-Path $outDir ($Slug + '.md')
if (Test-Path $file) { Write-Host "[!] $file already exists - edit it instead of duplicating." -ForegroundColor Yellow; exit 1 }

$body = [System.IO.File]::ReadAllText($tpl)
$body = $body.Replace('{{SLUG}}', $Slug).Replace('{{ONE_LINE}}', $Desc).Replace('{{TYPE}}', $Type).Replace('{{BODY}}', $Body).Replace('{{WHY}}', $Why).Replace('{{HOW}}', $How)
[System.IO.File]::WriteAllText($file, $body, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "[+] $file"

$idx = "- [$Slug]($Slug.md) - $Desc"
$ex = [System.IO.File]::ReadAllText($idxFile).TrimEnd(("`r`n").ToCharArray())
[System.IO.File]::WriteAllText($idxFile, $ex + "`r`n" + $idx + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("[+] index line added: " + (Split-Path $idxFile -Leaf))
if ($Shared) { Write-Host "    (shared/public lesson - make sure it has NO personal data)" -ForegroundColor DarkYellow }
Write-Host "OK - lesson '$Slug' captured." -ForegroundColor Green
