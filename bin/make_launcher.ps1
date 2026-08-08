<#
  make_launcher.ps1 - create a pinnable sonelle launcher (.lnk) with the app icon.
  The shortcut opens the sonelle TERMINAL (Windows Terminal if installed, else powershell.exe).
  Pin the .lnk to the taskbar. Re-run after moving sonelle or regenerating the icon.
  Usage:  powershell -File bin\make_launcher.ps1 [-NoStartMenu]
  Source is pure ASCII.
#>
param([switch]$NoStartMenu)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$sonelle = Join-Path $root 'bin\sonelle.ps1'
$ico = Join-Path $root 'assets\icon\sonelle.ico'
$ps  = (Get-Command powershell).Source
$wt  = Get-Command wt -ErrorAction SilentlyContinue

if (-not (Test-Path $sonelle)) { Write-Host "[X] entry script not found: $sonelle" -ForegroundColor Red; exit 1 }
if ($wt) {
  $target  = $wt.Source
  $lnkArgs = '-w 0 nt --title sonelle -d "' + $root + '" powershell -NoExit -ExecutionPolicy Bypass -File "' + $sonelle + '"'
  $mode    = 'terminal (Windows Terminal)'
} else {
  $target  = $ps
  $lnkArgs = '-NoExit -ExecutionPolicy Bypass -File "' + $sonelle + '"'
  $mode    = 'terminal (PowerShell)'
}
$lnkName = 'sonelle.lnk'
$desc    = 'sonelle terminal'
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
Write-Host "PIN: right-click Desktop 'sonelle' shortcut -> Show more options -> Pin to taskbar (or drag it onto the taskbar)."
