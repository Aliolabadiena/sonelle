<#
  make_launcher.ps1 - create a pinnable sonelle launcher (.lnk) with the app icon.
  DEFAULT: the shortcut opens the sonelle APP (bin\sonelle_app.ps1) - one window, many terminals
  as tabs. Use -Terminal for the old behavior (a single bare console, via Windows Terminal if
  installed, else powershell.exe). Pin the .lnk to the taskbar. Re-run after moving sonelle or
  regenerating the icon.
  Usage:  powershell -File bin\make_launcher.ps1 [-NoStartMenu] [-Terminal]
          (default) -> shortcut opens the sonelle APP (many terminals, one window)
          -Terminal -> shortcut opens a single sonelle terminal console
#>
param([switch]$NoStartMenu, [switch]$Terminal)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$sonelle = Join-Path $root 'bin\sonelle.ps1'
$appPs   = Join-Path $root 'bin\sonelle_app.ps1'
$ico  = Join-Path $root 'assets\icon\sonelle.ico'
$entryPs = if ($Terminal) { $sonelle } else { $appPs }
$lnkName = if ($Terminal) { 'sonelle terminal.lnk' } else { 'sonelle.lnk' }
$desc    = if ($Terminal) { 'sonelle terminal (single console)' } else { 'sonelle app (many terminals, one window)' }
if (-not (Test-Path $entryPs)) { Write-Host "[X] entry script not found: $entryPs" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $ico))  { Write-Host "[!] icon missing ($ico) - run assets\icon\make_icon.py first." -ForegroundColor Yellow }

$wt = Get-Command wt -ErrorAction SilentlyContinue
if (-not $Terminal) {
  # the app is a GUI window (not a console); launch it directly under -Sta, never via wt
  $target  = (Get-Command powershell).Source
  $lnkArgs = '-NoProfile -Sta -ExecutionPolicy Bypass -File "' + $appPs + '"'
} elseif ($wt) {
  $target  = $wt.Source
  $lnkArgs = '-w 0 nt --title sonelle -d "' + $root + '" powershell -NoExit -ExecutionPolicy Bypass -File "' + $sonelle + '"'
} else {
  $target  = (Get-Command powershell).Source
  $lnkArgs = '-NoExit -ExecutionPolicy Bypass -File "' + $sonelle + '"'
}

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
$mode = if (-not $Terminal) { 'sonelle app (many terminals, one window)' } elseif ($wt) { 'Windows Terminal' } else { 'PowerShell (install Windows Terminal for tabbed multi-instance)' }
Write-Host ("launcher target: {0}" -f $mode)
$pinName = $lnkName -replace '\.lnk$', ''
Write-Host ("PIN: right-click Desktop '{0}' shortcut -> Show more options -> Pin to taskbar (or drag it onto the taskbar)." -f $pinName)
