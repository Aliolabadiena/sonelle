<#
  make_launcher.ps1 - create a pinnable sonelle launcher (.lnk) with the app icon.
  DEFAULT: the shortcut opens the liquid-glass sonelle APP (Python / pywebview, via
  bin\sonelle_gui.ps1) - one window, many terminals as tabs.
    -Classic  -> the classic WinForms host (bin\sonelle_app.ps1)
    -Terminal -> a single bare console (Windows Terminal if installed, else powershell.exe)
  Pin the .lnk to the taskbar. Re-run after moving sonelle or regenerating the icon.
  Usage:  powershell -File bin\make_launcher.ps1 [-NoStartMenu] [-Classic] [-Terminal]
  Source is pure ASCII.
#>
param([switch]$NoStartMenu, [switch]$Classic, [switch]$Terminal)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$sonelle = Join-Path $root 'bin\sonelle.ps1'
$guiPs   = Join-Path $root 'bin\sonelle_gui.ps1'
$appPs   = Join-Path $root 'bin\sonelle_app.ps1'
$ico = Join-Path $root 'assets\icon\sonelle.ico'
$ps  = (Get-Command powershell).Source
$wt  = Get-Command wt -ErrorAction SilentlyContinue

if ($Terminal) {
  if (-not (Test-Path $sonelle)) { Write-Host "[X] entry script not found: $sonelle" -ForegroundColor Red; exit 1 }
  if ($wt) {
    $target  = $wt.Source
    $lnkArgs = '-w 0 nt --title sonelle -d "' + $root + '" powershell -NoExit -ExecutionPolicy Bypass -File "' + $sonelle + '"'
  } else {
    $target  = $ps
    $lnkArgs = '-NoExit -ExecutionPolicy Bypass -File "' + $sonelle + '"'
  }
  $lnkName = 'sonelle terminal.lnk'
  $desc    = 'sonelle terminal (single console)'
  $mode    = if ($wt) { 'single console (Windows Terminal)' } else { 'single console (PowerShell)' }
} elseif ($Classic) {
  if (-not (Test-Path $appPs)) { Write-Host "[X] entry script not found: $appPs" -ForegroundColor Red; exit 1 }
  $target  = $ps
  $lnkArgs = '-NoProfile -Sta -ExecutionPolicy Bypass -File "' + $appPs + '"'
  $lnkName = 'sonelle classic.lnk'
  $desc    = 'sonelle classic (WinForms tabs)'
  $mode    = 'classic WinForms app'
} else {
  if (-not (Test-Path $guiPs)) { Write-Host "[X] entry script not found: $guiPs" -ForegroundColor Red; exit 1 }
  $target  = $ps
  $lnkArgs = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $guiPs + '"'
  $lnkName = 'sonelle.lnk'
  $desc    = 'sonelle (liquid glass app)'
  $mode    = 'liquid-glass app (Python / pywebview)'
}
if (-not (Test-Path $ico)) { Write-Host "[!] icon missing ($ico) - run assets\icon\make_icon.py first." -ForegroundColor Yellow }

function New-Lnk($path) {
  $sh = New-Object -ComObject WScript.Shell
  $l = $sh.CreateShortcut($path)
  $l.TargetPath = $target
  $l.Arguments = $lnkArgs
  $l.WorkingDirectory = $root
  if (Test-Path $ico) { $l.IconLocation = ($ico + ',0') }
  $l.Description = $desc
  $l.Save()
  Write-Host "[+] $path"
}

New-Lnk (Join-Path ([Environment]::GetFolderPath('Desktop')) $lnkName)
if (-not $NoStartMenu) {
  $sm = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
  if (Test-Path $sm) { New-Lnk (Join-Path $sm $lnkName) }
}
Write-Host ""
Write-Host ("launcher target: {0}" -f $mode)
$pinName = $lnkName -replace '\.lnk$', ''
Write-Host ("PIN: right-click Desktop '{0}' shortcut -> Show more options -> Pin to taskbar (or drag it onto the taskbar)." -f $pinName)
