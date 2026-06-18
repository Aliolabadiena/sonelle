<#
  make_launcher.ps1 - create a pinnable sonelle launcher (.lnk) with the app icon.
  Target = Windows Terminal if installed (nicer + tabs), else powershell.exe. The .lnk opens the
  sonelle terminal (bin\sonelle.ps1) from ANYWHERE - pin it to the taskbar. Re-run after moving sonelle or
  regenerating the icon.
  Usage:  powershell -File bin\make_launcher.ps1 [-NoStartMenu]
#>
param([switch]$NoStartMenu)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$sonelle = Join-Path $root 'bin\sonelle.ps1'
$ico  = Join-Path $root 'assets\icon\sonelle.ico'
if (-not (Test-Path $sonelle)) { Write-Host "[X] sonelle.ps1 not found: $sonelle" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $ico))  { Write-Host "[!] icon missing ($ico) - run assets\icon\make_icon.py first." -ForegroundColor Yellow }

$wt = Get-Command wt -ErrorAction SilentlyContinue
if ($wt) {
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
  $l.Description = 'sonelle terminal'
  $l.Save()
  Write-Host "[+] $path"
}

New-Lnk (Join-Path ([Environment]::GetFolderPath('Desktop')) 'sonelle.lnk')
if (-not $NoStartMenu) {
  $sm = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
  if (Test-Path $sm) { New-Lnk (Join-Path $sm 'sonelle.lnk') }
}
Write-Host ""
$mode = if ($wt) { 'Windows Terminal' } else { 'PowerShell (install Windows Terminal for tabbed multi-instance)' }
Write-Host ("launcher target: {0}" -f $mode)
Write-Host "PIN: right-click Desktop 'sonelle' shortcut -> Show more options -> Pin to taskbar (or drag it onto the taskbar)."
