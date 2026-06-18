<#
  log_lesson.ps1 - SELF-IMPROVE capture. Persist a lesson (gotcha / feedback / fact)
  into memory\ after a task, so the next session recalls it. Hub = parent of tools\.

  Usage:
    .\log_lesson.ps1 -Slug build-needs-keys -Type gotcha `
      -Desc "Always build with --dart-define keys" `
      -Body "A keyless build runs offline and looks like data loss." `
      -Why "Offline build seeds ~20 rows" -How "Always pass the keys; verify len."
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Slug,
  [Parameter(Mandatory = $true)][string]$Desc,
  [Parameter(Mandatory = $true)][string]$Body,
  [ValidateSet('gotcha','feedback','project','reference')][string]$Type = 'gotcha',
  [string]$Why = '',
  [string]$How = '',
  [string]$Hub = ''
)
$ErrorActionPreference = 'Stop'
$engine = Split-Path $PSScriptRoot -Parent
$hub    = if ($Hub) { $Hub } else { $engine }
$memDir = Join-Path $hub 'memory'
$tpl    = Join-Path $engine 'templates\lesson.template.md'
if (-not (Test-Path $memDir)) { New-Item -ItemType Directory -Path $memDir -Force | Out-Null }
$memIndex = Join-Path $memDir 'MEMORY.md'
if (-not (Test-Path $memIndex)) { [System.IO.File]::WriteAllText($memIndex, "# Memory index", (New-Object System.Text.UTF8Encoding($false))) }

if ($Slug -notmatch '^[a-z0-9_-]+$') { Write-Host "[X] Slug must be a-z 0-9 _ - only." -ForegroundColor Red; exit 1 }
$file = Join-Path $memDir ($Slug + '.md')
if (Test-Path $file) { Write-Host "[!] $file already exists - edit it instead of duplicating." -ForegroundColor Yellow; exit 1 }

$body = [System.IO.File]::ReadAllText($tpl)
$body = $body.Replace('{{SLUG}}', $Slug).Replace('{{ONE_LINE}}', $Desc).Replace('{{TYPE}}', $Type).Replace('{{BODY}}', $Body).Replace('{{WHY}}', $Why).Replace('{{HOW}}', $How)
[System.IO.File]::WriteAllText($file, $body, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "[+] $file"

$idx = "- [$Slug]($Slug.md) - $Desc"
$ex = [System.IO.File]::ReadAllText($memIndex).TrimEnd(("`r`n").ToCharArray())
[System.IO.File]::WriteAllText($memIndex, $ex + "`r`n" + $idx + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Host "[+] memory\MEMORY.md index line added"
Write-Host "OK - lesson '$Slug' captured." -ForegroundColor Green
